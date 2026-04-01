//! Text capture: simulates Ctrl+C and reads clipboard content.
//! Mirrors macOS TextCapture.swift behavior.

use tracing::warn;
use thiserror::Error;

#[cfg(windows)]
use windows::{
    Win32::UI::Input::KeyboardAndMouse::*,
    Win32::Foundation::*,
    Win32::System::DataExchange::{OpenClipboard, GetClipboardData, CloseClipboard},
    Win32::System::Memory::{GlobalLock, GlobalUnlock},
};

#[derive(Error, Debug)]
pub enum CaptureError {
    #[error("Clipboard empty or inaccessible")]
    ClipboardEmpty,
    #[error("No valid word in clipboard")]
    NoValidWord,
    #[error("Win32 error: {0}")]
    Win32(String),
}

fn is_valid_word(s: &str) -> bool {
    let s = s.trim();
    if s.is_empty() || s.len() > 64 {
        return false;
    }
    s.chars().any(|c| c.is_alphabetic())
        && !s.contains(' ')
        && s.chars().filter(|c| !c.is_alphanumeric()).count() <= 1
}

#[cfg(windows)]
pub fn simulate_ctrl_c() -> Result<(), CaptureError> {
    unsafe {
        let keybd_down = |vk: VIRTUAL_KEY| -> Result<(), CaptureError> {
            let scan = MapVirtualKeyW(vk.0 as u32, MAP_VIRTUAL_KEY_TYPE(0)) as u16;
            let input = KEYBDINPUT {
                wVk: vk,
                wScan: scan,
                dwFlags: KEYBD_EVENT_FLAGS(0),
                time: 0,
                dwExtraInfo: 0,
            };
            let mut inputs = [INPUT {
                r#type: INPUT_KEYBOARD,
                Anonymous: INPUT_0 { ki: input },
            }];
            let result = SendInput(&mut inputs, std::mem::size_of::<INPUT>() as i32);
            if result != 1 {
                return Err(CaptureError::Win32(format!("SendInput failed: {}", result)));
            }
            Ok(())
        };

        let keybd_up = |vk: VIRTUAL_KEY| -> Result<(), CaptureError> {
            let scan = MapVirtualKeyW(vk.0 as u32, MAP_VIRTUAL_KEY_TYPE(0)) as u16;
            let input = KEYBDINPUT {
                wVk: vk,
                wScan: scan,
                dwFlags: KEYEVENTF_KEYUP,
                time: 0,
                dwExtraInfo: 0,
            };
            let mut inputs = [INPUT {
                r#type: INPUT_KEYBOARD,
                Anonymous: INPUT_0 { ki: input },
            }];
            let result = SendInput(&mut inputs, std::mem::size_of::<INPUT>() as i32);
            if result != 1 {
                return Err(CaptureError::Win32(format!("SendInput keyup failed: {}", result)));
            }
            Ok(())
        };

        keybd_down(VK_CONTROL)?;
        keybd_down(VIRTUAL_KEY(b'C' as u16))?;
        keybd_up(VIRTUAL_KEY(b'C' as u16))?;
        keybd_up(VK_CONTROL)?;

        Ok(())
    }
}

#[cfg(windows)]
pub fn read_clipboard_word() -> Result<String, CaptureError> {
    use std::ptr;

    unsafe {
        OpenClipboard(HWND(ptr::null_mut()))
            .map_err(|e| CaptureError::Win32(e.to_string()))?;

        let result = (|| -> Result<String, CaptureError> {
            // CF_UNICODETEXT = 13
            let handle = GetClipboardData(13u32)
                .map_err(|_| CaptureError::ClipboardEmpty)?;

            // GetClipboardData returns HANDLE; GlobalLock/Unlock need HGLOBAL
            let hglobal = HGLOBAL(handle.0);
            let ptr = GlobalLock(hglobal);
            if ptr.is_null() {
                return Err(CaptureError::ClipboardEmpty);
            }

            let text = wc_to_string(ptr as *const u16);
            let _ = GlobalUnlock(hglobal);

            let word = text.trim().to_string();
            if !is_valid_word(&word) {
                warn!("Clipboard content not a valid word: {:?}", word);
                return Err(CaptureError::NoValidWord);
            }

            Ok(word)
        })();

        let _ = CloseClipboard();
        result
    }
}

fn wc_to_string(ptr: *const u16) -> String {
    if ptr.is_null() {
        return String::new();
    }
    unsafe {
        let len = (0..).take_while(|&i| *ptr.add(i) != 0).count();
        let slice = std::slice::from_raw_parts(ptr, len);
        String::from_utf16_lossy(slice)
    }
}

#[cfg(windows)]
pub fn capture_word() -> Result<String, CaptureError> {
    simulate_ctrl_c()?;
    std::thread::sleep(std::time::Duration::from_millis(50));
    read_clipboard_word()
}

#[cfg(not(windows))]
pub fn capture_word() -> Result<String, CaptureError> {
    Err(CaptureError::ClipboardEmpty)
}
