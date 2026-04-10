//! Bubble notification window and system tray integration.
//! Creates a borderless, always-on-top window at cursor position.

use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use tauri::{AppHandle, Emitter, Listener, Manager, WebviewUrl, WebviewWindowBuilder};
use tracing::info;

pub fn create_tray(app: &AppHandle) -> Result<(), String> {
    use tauri::tray::{TrayIconBuilder, MouseButton, MouseButtonState, TrayIconEvent};
    use tauri::menu::{MenuBuilder, MenuItemBuilder};

    let setup_item = MenuItemBuilder::with_id("setup", "Settings...").build(app)
        .map_err(|e| e.to_string())?;
    let quit_item = MenuItemBuilder::with_id("quit", "Quit Words Hunter").build(app)
        .map_err(|e| e.to_string())?;

    let menu = MenuBuilder::new(app)
        .item(&setup_item)
        .separator()
        .item(&quit_item)
        .build()
        .map_err(|e| e.to_string())?;

    let _tray = TrayIconBuilder::new()
        .icon(app.default_window_icon().unwrap().clone())
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| {
            match event.id().as_ref() {
                "setup" => {
                    if let Err(e) = show_setup_window(app) {
                        tracing::error!("Failed to show setup window: {}", e);
                    }
                }
                "quit" => {
                    info!("Quit requested from tray");
                    app.exit(0);
                }
                _ => {}
            }
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                if let Some(window) = tray.app_handle().get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
        })
        .build(app)
        .map_err(|e| e.to_string())?;

    info!("System tray created");
    Ok(())
}

pub fn show_setup_window(app: &AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("setup") {
        let _ = window.show();
        let _ = window.set_focus();
        return Ok(());
    }

    WebviewWindowBuilder::new(app, "setup", WebviewUrl::App(PathBuf::from("setup.html")))
        .title("Words Hunter Settings")
        .inner_size(520.0, 580.0)
        .resizable(false)
        .center()
        .build()
        .map_err(|e| e.to_string())?;

    Ok(())
}

pub enum BubbleStatus {
    Success,
    Captured,
}

static BUBBLE_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Show the bubble notification window at the cursor position
pub fn show_bubble(app: &AppHandle, word: &str) -> Result<(), String> {
    show_bubble_with_status(app, word, BubbleStatus::Success)
}

pub fn show_bubble_captured(app: &AppHandle, word: &str) -> Result<(), String> {
    show_bubble_with_status(app, word, BubbleStatus::Captured)
}

fn show_bubble_with_status(app: &AppHandle, word: &str, status: BubbleStatus) -> Result<(), String> {
    #[cfg(windows)]
    let (x, y) = get_cursor_position();

    #[cfg(not(windows))]
    let (x, y) = (100, 100);

    let id = BUBBLE_COUNTER.fetch_add(1, Ordering::Relaxed);
    let window_label = format!("bubble-{}", id);

    // Close any previous bubble window
    if id > 0 {
        let prev_label = format!("bubble-{}", id - 1);
        if let Some(old) = app.get_webview_window(&prev_label) {
            let _ = old.close();
        }
    }

    let window = WebviewWindowBuilder::new(
        app,
        &window_label,
        WebviewUrl::App(PathBuf::from("bubble.html")),
    )
    .inner_size(200.0, 60.0)
    .position(x as f64, y as f64)
    .decorations(false)
    .transparent(true)
    .always_on_top(true)
    .skip_taskbar(true)
    .resizable(false)
    .focused(false)
    .build()
    .map_err(|e| e.to_string())?;

    let word_clone = word.to_string();
    let app_clone = app.clone();
    let label_clone = window_label.clone();
    let event_name = match status {
        BubbleStatus::Success => "show-bubble",
        BubbleStatus::Captured => "show-bubble-captured",
    };
    let event_name = event_name.to_string();
    window.once("tauri://created", move |_| {
        let app = app_clone;
        let w = word_clone;
        let label = label_clone;
        std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(100));
            if let Some(win) = app.get_webview_window(&label) {
                let _ = win.emit(&event_name, &w);
            }
        });
    });

    let dismiss_label = window_label.clone();
    let app_dismiss = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_secs(3));
        if let Some(w) = app_dismiss.get_webview_window(&dismiss_label) {
            let _ = w.close();
        }
    });

    Ok(())
}

#[cfg(windows)]
fn get_cursor_position() -> (i32, i32) {
    use windows::Win32::UI::WindowsAndMessaging::GetCursorPos;
    use windows::Win32::Foundation::POINT;
    unsafe {
        let mut point = POINT::default();
        if GetCursorPos(&mut point).is_ok() {
            (point.x, point.y)
        } else {
            (100, 100)
        }
    }
}
