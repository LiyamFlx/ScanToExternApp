//! Foreground-window capture/restore.
//!
//! Injection (UI Automation `set_value` or clipboard Ctrl+V) always targets the
//! window that currently has focus. But our own preview toast / popover steals
//! focus when shown, so by the time the user clicks "Inject" the focused window
//! is *ours*, not the Notepad / Word / browser they were scanning into.
//!
//! To fix this we record the user's foreground window the moment a scan arrives
//! (before any of our windows appear) and restore it just before injecting.
//! This is the Windows analogue of the Mac app's non-activating preview panel.

#[cfg(windows)]
mod imp {
    use std::sync::atomic::{AtomicIsize, Ordering};

    use windows::Win32::Foundation::HWND;
    use windows::Win32::System::Threading::GetCurrentProcessId;
    use windows::Win32::UI::WindowsAndMessaging::{
        GetForegroundWindow, GetWindowThreadProcessId, IsWindow, SetForegroundWindow,
    };

    static TARGET_HWND: AtomicIsize = AtomicIsize::new(0);

    /// Record the current foreground window as the injection target — unless it
    /// belongs to our own process (the preview/popover/settings windows), in
    /// which case we keep the previously captured target.
    pub fn capture_foreground() {
        unsafe {
            let hwnd = GetForegroundWindow();
            if hwnd.0.is_null() {
                return;
            }
            let mut pid: u32 = 0;
            GetWindowThreadProcessId(hwnd, Some(&mut pid));
            if pid == GetCurrentProcessId() {
                // Foreground is one of our own windows — don't overwrite the
                // real target the user was scanning into.
                return;
            }
            TARGET_HWND.store(hwnd.0 as isize, Ordering::SeqCst);
            log::debug!("[Focus] Captured target window (pid {})", pid);
        }
    }

    /// Bring the captured target window back to the foreground before injecting.
    /// Returns true if a still-valid target was restored.
    pub fn restore_foreground() -> bool {
        let raw = TARGET_HWND.load(Ordering::SeqCst);
        if raw == 0 {
            return false;
        }
        let hwnd = HWND(raw as *mut core::ffi::c_void);
        unsafe {
            if !IsWindow(Some(hwnd)).as_bool() {
                log::debug!("[Focus] Captured target no longer exists");
                return false;
            }
            // Allowed because we are the foreground process at click time, so we
            // may hand the foreground back to the window we took it from.
            let _ = SetForegroundWindow(hwnd);
        }
        // Give the window manager a moment to actually switch foreground before
        // keystrokes / UIA calls land.
        std::thread::sleep(std::time::Duration::from_millis(80));
        log::debug!("[Focus] Restored target window to foreground");
        true
    }
}

#[cfg(windows)]
pub use imp::{capture_foreground, restore_foreground};

#[cfg(not(windows))]
#[allow(dead_code)]
pub fn capture_foreground() {}

#[cfg(not(windows))]
#[allow(dead_code)]
pub fn restore_foreground() -> bool {
    false
}
