//! Bubble notification window and system tray integration.
//! Creates a borderless, always-on-top window at cursor position.
//! HTML/CSS/JS frontend for the bubble UI.

use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindowBuilder};
use tracing::{info, error};
use std::sync::OnceLock;

static BUBBLE_WINDOW: OnceLock<tauri::WebviewWindow> = OnceLock::new();

const BUBBLE_HTML: &str = r#"<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: transparent;
      font-family: 'Segoe UI', system-ui, sans-serif;
      overflow: hidden;
    }
    .bubble {
      display: flex;
      align-items: center;
      gap: 10px;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      padding: 10px 18px;
      border-radius: 24px;
      box-shadow: 0 4px 24px rgba(102, 126, 234, 0.5), 0 0 0 1px rgba(255,255,255,0.1);
      font-size: 15px;
      font-weight: 500;
      opacity: 0;
      transform: scale(0.8) translateY(10px);
      transition: opacity 0.2s ease-out, transform 0.2s ease-out;
      white-space: nowrap;
      user-select: none;
    }
    .bubble.show {
      opacity: 1;
      transform: scale(1) translateY(0);
    }
    .bubble .icon {
      width: 20px;
      height: 20px;
      flex-shrink: 0;
    }
    .bubble .checkmark {
      display: none;
    }
    .bubble.success .checkmark {
      display: block;
    }
    .bubble.success .word {
      display: none;
    }
    .bubble.fade-out {
      opacity: 0;
      transform: scale(0.9) translateY(-5px);
      transition: opacity 0.3s ease-in, transform 0.3s ease-in;
    }
  </style>
</head>
<body>
  <div class="bubble" id="bubble">
    <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
      <path d="M20 6L9 17l-5-5"/>
    </svg>
    <svg class="checkmark" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
      <circle cx="12" cy="12" r="10" stroke="rgba(255,255,255,0.4)" stroke-width="1"/>
      <path d="M8 12l3 3 5-5"/>
    </svg>
    <span class="word" id="word"></span>
  </div>
  <script>
    const { listen } = window.__TAURI__.event;
    let dismissTimer;

    listen('show-bubble', (event) => {
      const word = event.payload;
      const bubble = document.getElementById('bubble');
      const wordEl = document.getElementById('word');
      wordEl.textContent = word;
      bubble.className = 'bubble show';

      clearTimeout(dismissTimer);
      dismissTimer = setTimeout(() => {
        bubble.classList.add('fade-out');
        setTimeout(() => bubble.className = 'bubble', 350);
      }, 1500);
    });

    listen('show-bubble-success', (event) => {
      const word = event.payload;
      const bubble = document.getElementById('bubble');
      const wordEl = document.getElementById('word');
      wordEl.textContent = word;
      bubble.className = 'bubble success show';

      clearTimeout(dismissTimer);
      dismissTimer = setTimeout(() => {
        bubble.classList.add('fade-out');
        setTimeout(() => bubble.className = 'bubble', 350);
      }, 1500);
    });
  </script>
</body>
</html>"#;

const SETUP_HTML: &str = r#"<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: 'Segoe UI', system-ui, sans-serif;
      background: #f8f9fa;
      color: #333;
      min-height: 100vh;
    }
    .container {
      max-width: 480px;
      margin: 0 auto;
      padding: 32px 24px;
    }
    h1 {
      font-size: 22px;
      font-weight: 600;
      margin-bottom: 8px;
    }
    .subtitle {
      font-size: 13px;
      color: #666;
      margin-bottom: 32px;
    }
    .field {
      margin-bottom: 20px;
    }
    label {
      display: block;
      font-size: 12px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: #555;
      margin-bottom: 6px;
    }
    input {
      width: 100%;
      padding: 10px 12px;
      border: 1px solid #ddd;
      border-radius: 8px;
      font-size: 14px;
      background: white;
      transition: border-color 0.15s;
    }
    input:focus {
      outline: none;
      border-color: #667eea;
      box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
    }
    .hotkey-display {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 10px 12px;
      background: #eef0f5;
      border-radius: 8px;
      font-size: 14px;
      color: #444;
    }
    kbd {
      background: white;
      border: 1px solid #ccc;
      border-radius: 4px;
      padding: 2px 8px;
      font-size: 12px;
      font-family: monospace;
      box-shadow: 0 1px 0 #ccc;
    }
    .toggle {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 12px 0;
    }
    .toggle-label {
      font-size: 14px;
    }
    .toggle-desc {
      font-size: 12px;
      color: #888;
    }
    .switch {
      position: relative;
      width: 44px;
      height: 24px;
    }
    .switch input { opacity: 0; width: 0; height: 0; }
    .slider {
      position: absolute;
      cursor: pointer;
      top: 0; left: 0; right: 0; bottom: 0;
      background: #ccc;
      transition: 0.2s;
      border-radius: 24px;
    }
    .slider:before {
      position: absolute;
      content: "";
      height: 18px;
      width: 18px;
      left: 3px;
      bottom: 3px;
      background: white;
      transition: 0.2s;
      border-radius: 50%;
      box-shadow: 0 1px 3px rgba(0,0,0,0.2);
    }
    input:checked + .slider { background: #667eea; }
    input:checked + .slider:before { transform: translateX(20px); }
    .actions {
      display: flex;
      gap: 12px;
      margin-top: 28px;
    }
    button {
      flex: 1;
      padding: 12px;
      border: none;
      border-radius: 8px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      transition: opacity 0.15s, transform 0.1s;
    }
    button:active { transform: scale(0.98); }
    .btn-primary {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
    }
    .btn-secondary {
      background: #e5e7eb;
      color: #333;
    }
    .status {
      text-align: center;
      font-size: 13px;
      margin-top: 12px;
      min-height: 20px;
    }
    .status.ok { color: #10b981; }
    .status.error { color: #ef4444; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Words Hunter</h1>
    <p class="subtitle">Capture words from any app</p>

    <div class="field">
      <label>Trigger</label>
      <div class="hotkey-display">
        <kbd>Alt</kbd> + double-click on any word
      </div>
    </div>

    <div class="field">
      <label>Vault Path</label>
      <input type="text" id="vaultPath" placeholder="~/.wordshunter/vault">
    </div>

    <div class="field">
      <label>Template File</label>
      <input type="text" id="templatePath" placeholder="~/.wordshunter/template.md">
    </div>

    <div class="toggle">
      <div>
        <div class="toggle-label">Sound</div>
        <div class="toggle-desc">Play a sound on capture</div>
      </div>
      <label class="switch">
        <input type="checkbox" id="soundEnabled" checked>
        <span class="slider"></span>
      </label>
    </div>

    <div class="toggle">
      <div>
        <div class="toggle-label">Bubble</div>
        <div class="toggle-desc">Show notification on capture</div>
      </div>
      <label class="switch">
        <input type="checkbox" id="bubbleEnabled" checked>
        <span class="slider"></span>
      </label>
    </div>

    <div class="actions">
      <button class="btn-secondary" id="btnOpen">Open Vault</button>
      <button class="btn-primary" id="btnSave">Save</button>
    </div>
    <div class="status" id="status"></div>
  </div>

  <script>
    const { invoke } = window.__TAURI__.core;
    const { open } = window.__TAURI__.dialog;

    async function loadConfig() {
      try {
        const cfg = await invoke('get_config');
        if (cfg) {
          document.getElementById('vaultPath').value = cfg.vault_path || '';
          document.getElementById('templatePath').value = cfg.template_path || '';
          document.getElementById('soundEnabled').checked = cfg.sound_enabled !== false;
          document.getElementById('bubbleEnabled').checked = cfg.bubble_enabled !== false;
        }
      } catch(e) { console.error(e); }
    }

    async function saveConfig() {
      const status = document.getElementById('status');
      try {
        await invoke('save_config', {
          newConfig: {
            vault_path: document.getElementById('vaultPath').value,
            template_path: document.getElementById('templatePath').value,
            hotkey: 'Alt+double-click',
            sound_enabled: document.getElementById('soundEnabled').checked,
            bubble_enabled: document.getElementById('bubbleEnabled').checked
          }
        });
        status.textContent = 'Saved!';
        status.className = 'status ok';
        setTimeout(() => { status.textContent = ''; }, 2000);
      } catch(e) {
        status.textContent = 'Error: ' + e;
        status.className = 'status error';
      }
    }

    async function openVault() {
      const path = document.getElementById('vaultPath').value;
      if (path) {
        try { await open(path); } catch(e) { console.error(e); }
      }
    }

    document.getElementById('btnSave').addEventListener('click', saveConfig);
    document.getElementById('btnOpen').addEventListener('click', openVault);
    loadConfig();
  </script>
</body>
</html>"#;

pub fn create_tray(app: &AppHandle) -> Result<(), String> {
    use tauri::tray::{TrayIconBuilder, MouseButton, MouseButtonState, TrayIconEvent};
    use tauri::menu::{MenuBuilder, MenuItemBuilder};

    let setup_item = MenuItemBuilder::with_id("setup", "Settings...").build(app)?;
    let quit_item = MenuItemBuilder::with_id("quit", "Quit Words Hunter").build(app)?;

    let menu = MenuBuilder::new(app)
        .item(&setup_item)
        .separator()
        .item(&quit_item)
        .build()?;

    let _tray = TrayIconBuilder::new()
        .icon(app.default_window_icon().unwrap().clone())
        .menu(&menu)
        .menu_on_left_click(false)
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
    let existing = app.get_webview_window("setup");
    if let Some(window) = existing {
        let _ = window.show();
        let _ = window.set_focus();
        return Ok(());
    }

    WebviewWindowBuilder::new(app, "setup", WebviewUrl::Inline(SETUP_HTML.into()))
        .title("Words Hunter Settings")
        .inner_size(520.0, 580.0)
        .resizable(false)
        .center()
        .build()
        .map_err(|e| e.to_string())?;

    Ok(())
}

/// Show the bubble notification window at the cursor position
pub fn show_bubble(app: &AppHandle, word: &str) -> Result<(), String> {
    // Get cursor position
    #[cfg(windows)]
    let (x, y) = get_cursor_position();

    #[cfg(not(windows))]
    let (x, y) = (100, 100);

    // Show a small bubble window at cursor
    let window_label = format!("bubble-{}", std::process::id());

    // Remove old bubble if exists
    if let Some(old) = app.get_webview_window(&window_label) {
        let _ = old.close();
    }

    let window = WebviewWindowBuilder::new(
        app,
        &window_label,
        WebviewUrl::Inline(BUBBLE_HTML.into()),
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

    // Emit the word to the bubble window after it loads
    let word_clone = word.to_string();
    window.once("tauri://created", move |_| {
        let app = app.clone();
        let w = word_clone.clone();
        std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(100));
            if let Some(window) = app.get_webview_window(&format!("bubble-{}", std::process::id())) {
                let _ = window.emit("show-bubble", &w);
            }
        });
    })?;

    // Auto-dismiss after 2 seconds
    let dismiss_window_label = window_label.clone();
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_secs(2));
        if let Some(w) = app.get_webview_window(&dismiss_window_label) {
            let _ = w.close();
        }
    });

    Ok(())
}

#[cfg(windows)]
fn get_cursor_position() -> (i32, i32) {
    use windows::Win32::UI::Input::KeyboardAndMouse::GetCursorPos;
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
