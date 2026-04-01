pub mod hotkey;
pub mod text_capture;
pub mod lemmatizer;
pub mod vault;
pub mod dictionary;
pub mod bubble;
pub mod audio;
pub mod config;

use std::sync::Mutex;
use tauri::{AppHandle, Listener, Manager};
use tracing::{info, error, warn};

pub struct AppState {
    pub config: Mutex<Option<config::AppConfig>>,
}

fn setup_logging() {
    let log_dir = dirs::data_local_dir()
        .unwrap_or_else(|| std::path::PathBuf::from("."))
        .join("WordsHunter")
        .join("logs");

    std::fs::create_dir_all(&log_dir).ok();

    let file_appender = tracing_subscriber::fmt::writer::MakeWriterExt::and(
        std::io::stdout,
        std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(log_dir.join("words-hunter.log"))
            .unwrap_or_else(|_| {
                std::fs::File::create(log_dir.join("words-hunter.log")).unwrap()
            }),
    );

    tracing_subscriber::fmt()
        .with_writer(file_appender)
        .with_ansi(false)
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive(tracing::Level::INFO.into()),
        )
        .init();
}

#[cfg_attr(windows, allow(unused))]
pub fn run() {
    setup_logging();
    info!("Words Hunter starting up...");

    let result = std::panic::catch_unwind(|| {
        tauri::Builder::default()
            .plugin(tauri_plugin_log::Builder::new().build())
            .plugin(tauri_plugin_shell::init())
            .plugin(tauri_plugin_notification::init())
            .plugin(tauri_plugin_clipboard_manager::init())
            .plugin(tauri_plugin_dialog::init())
            .plugin(tauri_plugin_fs::init())
            .manage(AppState {
                config: Mutex::new(None),
            })
            .setup(|app| {
                info!("Tauri app setup starting...");

                // Load config
                let config = config::load_config();
                if let Some(ref cfg) = config {
                    info!("Config loaded: vault={}", cfg.vault_path);
                } else {
                    warn!("No config found — using defaults");
                }

                {
                    let state = app.state::<AppState>();
                    *state.config.lock().unwrap() = config;
                }

                // Initialize system tray
                bubble::create_tray(app.handle())?;

                // Start hotkey listener
                hotkey::start_hotkey_listener(app.handle().clone())?;

                // Listen for hotkey events and run the capture flow
                let app_handle = app.handle().clone();
                app.listen("hotkey-triggered", move |_event| {
                    let app = app_handle.clone();
                    tokio::spawn(async move {
                        capture_and_process_word(app).await;
                    });
                });

                info!("Words Hunter setup complete");
                Ok(())
            })
            .invoke_handler(tauri::generate_handler![
                get_config,
                save_config,
                open_setup_window,
            ])
            .run(tauri::generate_context!())
    });

    if let Err(e) = result {
        error!("Fatal error: {:?}", e);
        std::process::exit(1);
    }
}

#[tauri::command]
fn get_config(state: tauri::State<AppState>) -> Option<config::AppConfig> {
    state.config.lock().unwrap().clone()
}

#[tauri::command]
fn save_config(state: tauri::State<AppState>, new_config: config::AppConfig) -> Result<(), String> {
    config::save_config(&new_config).map_err(|e| e.to_string())?;
    *state.config.lock().unwrap() = Some(new_config);
    Ok(())
}

#[tauri::command]
fn open_setup_window(app: AppHandle) -> Result<(), String> {
    bubble::show_setup_window(&app)
}

/// Full word capture flow: triggered by hotkey event
async fn capture_and_process_word(app: AppHandle) {
    let word = match text_capture::capture_word() {
        Ok(w) => w,
        Err(e) => {
            warn!("Failed to capture word: {:?}", e);
            return;
        }
    };

    info!("Captured word: {}", word);

    let lemma = lemmatizer::lemmatize(&word);
    info!("Lemmatized: {} -> {}", word, lemma);

    // Get config
    let config = {
        let state = app.state::<AppState>();
        state.config.lock().unwrap().clone()
    };

    let (vault_path, template_path, sound_enabled, bubble_enabled) = match config {
        Some(cfg) => (cfg.vault_path, cfg.template_path, cfg.sound_enabled, cfg.bubble_enabled),
        None => {
            warn!("No config loaded, cannot process word");
            return;
        }
    };

    // Check deduplication
    if vault::word_exists(&vault_path, &word) {
        info!("Word already exists in vault, skipping: {}", word);
        return;
    }

    // Dictionary lookup (async, non-blocking)
    let vars = match dictionary::lookup_word(&word).await {
        Ok(result) => result.into_vars(),
        Err(e) => {
            warn!("Dictionary lookup failed: {:?}", e);
            std::collections::HashMap::new()
        }
    };

    // Create vault file
    match vault::create_word_page(&vault_path, &template_path, &word, &lemma, vars) {
        Ok(_) => info!("Word page created: {}", word),
        Err(e) => {
            error!("Failed to create word page: {:?}", e);
            return;
        }
    }

    // Show bubble
    if bubble_enabled {
        if let Err(e) = bubble::show_bubble(&app, &word) {
            warn!("Failed to show bubble: {}", e);
        }
    }

    // Play sound
    if sound_enabled {
        audio::play_pop();
    }
}
