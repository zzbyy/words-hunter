//! Text capture: simulates Ctrl+C and reads clipboard content.
//! Mirrors macOS TextCapture.swift behavior.

use tracing::{debug, info, warn};
use thiserror::Error;

#[cfg(windows)]
use windows::{
    Win32::UI::Input::KeyboardAndMouse::*,
    Win32::UI::WindowsAndMessaging::*,
    Win32::Foundation::*,
    Win32::System::Threading::*,
    Win32::System::LibraryLoader::*,
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
    // Must contain at least one letter
    s.chars().any(|c| c.is_alphabetic())
        // Should not be a sentence/phrase
        && !s.contains(' ')
        // Should not have many special chars
        && s.chars().filter(|c| !c.is_alphanumeric()).count() <= 1
}

#[cfg(windows)]
pub fn simulate_ctrl_c() -> Result<(), CaptureError> {
    unsafe {
        // Alt is VK_MENU (0x12), Ctrl is VK_CONTROL (0x11), C is 'C' (0x43)
        let keybd_down = |vk: u16| -> Result<(), CaptureError> {
            let scan = MapVirtualKeyW(vk as u32, 0) as u16;
            let input = KEYBDINPUT {
                wVk: vk,
                wScan: scan,
                dwFlags: 0,
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

        let keybd_up = |vk: u16| -> Result<(), CaptureError> {
            let scan = MapVirtualKeyW(vk as u32, 0) as u16;
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

        // Ctrl down
        keybd_down(VK_CONTROL)?;
        // C down
        keybd_down(b'C' as u16)?;
        // C up
        keybd_up(b'C' as u16)?;
        // Ctrl up
        keybd_up(VK_CONTROL)?;

        Ok(())
    }
}

#[cfg(windows)]
pub fn read_clipboard_word() -> Result<String, CaptureError> {
    use std::ptr;

    unsafe {
        if !OpenClipboard(HWND(ptr::null_mut())).as_bool() {
            return Err(CaptureError::Win32("OpenClipboard failed".to_string()));
        }

        let result = (|| -> Result<String, CaptureError> {
            let handle = GetClipboardData(CF_UNICODETEXT);
            if handle.is_invalid() {
                return Err(CaptureError::ClipboardEmpty);
            }

            let ptr = windows::Win32::System::Memory::GlobalLock(handle.0 as *mut _);
            if ptr.is_null() {
                return Err(CaptureError::ClipboardEmpty);
            }

            let text = wc_to_string(ptr as *const u16);
            windows::Win32::System::Memory::GlobalUnlock(handle.0);

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
    // Small delay to let clipboard update
    std::thread::sleep(std::time::Duration::from_millis(50));
    read_clipboard_word()
}

#[cfg(not(windows))]
pub fn capture_word() -> Result<String, CaptureError> {
    Err(CaptureError::ClipboardEmpty)
}
