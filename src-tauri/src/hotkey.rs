//! Global Alt+double-click hotkey using Win32 low-level mouse hook.
//! Alt+double-click in any application triggers word capture.

use std::sync::atomic::{AtomicBool, Ordering};
use std::cell::RefCell;
use tauri::{AppHandle, Manager};
use tracing::{info, error, debug, warn};

#[cfg(windows)]
use windows::{
    Win32::Foundation::*,
    Win32::UI::Input::KeyboardAndMouse::*,
    Win32::UI::WindowsAndMessaging::*,
    Win32::System::Threading::*,
    Win32::System::LibraryLoader::*,
};

thread_local! {
    static APP_HANDLE: RefCell<Option<AppHandle>> = RefCell::new(None);
}

static HOTKEY_RUNNING: AtomicBool = AtomicBool::new(false);

/// Check if Alt key is currently held
#[cfg(windows)]
fn is_alt_pressed() -> bool {
    unsafe {
        (GetAsyncKeyState(VK_MENU.0 as i32) & 0x8000) != 0
    }
}

#[cfg(windows)]
pub fn start_hotkey_listener(app: AppHandle) -> Result<(), String> {
    use std::thread;

    if HOTKEY_RUNNING.swap(true, Ordering::SeqCst) {
        return Ok(());
    }

    // Store app handle in thread-local for use in the hook callback
    APP_HANDLE.with(|h| {
        *h.borrow_mut() = Some(app.clone());
    });

    std::thread::spawn(move || {
        info!("Hotkey listener thread started");

        unsafe {
            let hook_proc: HOOKPROC = Some(hook_callback);

            let hook = SetWindowsHookExW(WH_MOUSE_LL, hook_proc, HINSTANCE(0), 0);
            let hook = match hook {
                Ok(h) => {
                    info!("Mouse hook installed");
                    h
                }
                Err(e) => {
                    error!("Failed to install mouse hook: {:?}", e);
                    HOTKEY_RUNNING.store(false, Ordering::SeqCst);
                    return;
                }
            };

            // Message loop
            let mut msg = MSG::default();
            while HOTKEY_RUNNING.load(Ordering::SeqCst) {
                let ret = PeekMessageW(&mut msg, HWND(0), 0, 0, PM_REMOVE);
                if ret.as_bool() {
                    if msg.message == WM_QUIT {
                        break;
                    }
                    TranslateMessage(&msg);
                    DispatchMessageW(&msg);
                } else {
                    // No message — sleep briefly to avoid spinning
                    std::thread::sleep(std::time::Duration::from_millis(10));
                }
            }

            let _ = UnhookWindowsHookEx(hook);
            info!("Mouse hook uninstalled");
        }

        HOTKEY_RUNNING.store(false, Ordering::SeqCst);
        info!("Hotkey listener thread exiting");
    });

    Ok(())
}

// Low-level mouse hook callback
#[cfg(windows)]
unsafe extern "system" fn hook_callback(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code >= 0 && wparam.0 as u32 == WM_LBUTTONDBLCLK {
        let mouse_struct = *(lparam.0 as *const MSLLHOOKSTRUCT);
        let x = mouse_struct.pt.x;
        let y = mouse_struct.pt.y;

        if is_alt_pressed() {
            debug!("Alt+double-click at ({}, {})", x, y);
            APP_HANDLE.with(|h| {
                if let Some(ref app) = *h.borrow() {
                    let _ = app.emit("hotkey-triggered", (x, y));
                }
            });
        }
    }

    CallNextHookEx(HWND(0), code, wparam, lparam)
}

#[cfg(not(windows))]
pub fn start_hotkey_listener(_app: AppHandle) -> Result<(), String> {
    warn!("Hotkey listener only implemented on Windows");
    Ok(())
}
