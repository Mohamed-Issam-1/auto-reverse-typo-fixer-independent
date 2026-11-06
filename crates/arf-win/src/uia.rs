//! UI Automation focus diagnostics (no keyboard hook, no text collection).
//! This does NOT unlock browser correction; browsers remain fail-closed in focus.rs.

use std::time::Duration;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FocusSafety {
    Password,
    NonPassword,
    Unknown,
}

/// Fail closed if either focus or the IsPassword property cannot be confirmed.
pub fn classify(is_password: Option<bool>, has_focus: Option<bool>) -> FocusSafety {
    match (is_password, has_focus) {
        (Some(true), Some(true)) => FocusSafety::Password,
        (Some(false), Some(true)) => FocusSafety::NonPassword,
        _ => FocusSafety::Unknown,
    }
}

/// Two UIA focus reads must refer to the same logical element before a
/// NonPassword sample can be published. This is NOT a live pre-injection check.
#[cfg(any(windows, test))]
fn classify_with_identity(
    is_password: Option<bool>,
    has_focus: Option<bool>,
    same_element: Option<bool>,
) -> FocusSafety {
    if same_element != Some(true) {
        return FocusSafety::Unknown;
    }
    classify(is_password, has_focus)
}

#[cfg(windows)]
pub(crate) fn query_focused() -> Result<(i32, FocusSafety), String> {
    use windows::Win32::System::Com::{
        CoCreateInstance, CoInitializeEx, CoUninitialize, CLSCTX_INPROC_SERVER,
        COINIT_MULTITHREADED,
    };
    use windows::Win32::UI::Accessibility::{CUIAutomation, IUIAutomation};

    // This function is called on its own MTA thread, never the hook or UI thread.
    unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) }
        .ok()
        .map_err(|e| format!("COM initialization failed: {e}"))?;

    struct ComGuard;
    impl Drop for ComGuard {
        fn drop(&mut self) {
            // Balanced with the successful CoInitializeEx above, on this same thread.
            unsafe { CoUninitialize() };
        }
    }
    let _com_guard = ComGuard;

    // Both COM interface objects are scoped to this MTA thread.
    let automation: IUIAutomation =
        unsafe { CoCreateInstance(&CUIAutomation, None, CLSCTX_INPROC_SERVER) }
            .map_err(|e| format!("UI Automation initialization failed: {e}"))?;

    let element = unsafe { automation.GetFocusedElement() }
        .map_err(|e| format!("GetFocusedElement failed: {e}"))?;

    // Do NOT query Value, TextPattern, Name, or other user content.
    let pid = unsafe { element.CurrentProcessId() }.unwrap_or_default();
    let password = unsafe { element.CurrentIsPassword() }
        .ok()
        .map(|v| v.as_bool());
    let focused = unsafe { element.CurrentHasKeyboardFocus() }
        .ok()
        .map(|v| v.as_bool());

    // Never interpret a property snapshot as safe if the logical focus moved
    // while it was read. CompareElements compares UIA element identity without
    // reading Value, Name, TextPattern, or any user text.
    let refocused = unsafe { automation.GetFocusedElement() }.ok();
    let same_element = refocused
        .and_then(|current| unsafe { automation.CompareElements(&element, &current) }.ok())
        .map(|result| result.as_bool());

    Ok((pid, classify_with_identity(password, focused, same_element)))
}

/// One-time, read-only probe. No key interception or text injection is enabled.
pub fn run_diagnostic() -> i32 {
    println!("UIA diagnostic only: focus the test field within 8 seconds.");
    let worker = std::thread::spawn(|| {
        std::thread::sleep(Duration::from_secs(8));
        #[cfg(windows)]
        {
            query_focused()
        }
        #[cfg(not(windows))]
        {
            Err::<(i32, FocusSafety), String>("Windows is required".into())
        }
    });
    match worker.join() {
        Ok(Ok((pid, classification))) => {
            println!("Focused process ID: {pid}");
            println!("Focus classification: {classification:?}");
            println!("No text was read or stored.");
            0
        }
        Ok(Err(err)) => {
            eprintln!("UIA diagnostic: {err}");
            1
        }
        Err(_) => {
            eprintln!("UIA diagnostic thread failed");
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classified_focused_fields() {
        assert_eq!(classify(Some(true), Some(true)), FocusSafety::Password);
        assert_eq!(classify(Some(false), Some(true)), FocusSafety::NonPassword);
    }

    #[test]
    fn uncertain_state_blocks_correction() {
        assert_eq!(classify(Some(false), Some(false)), FocusSafety::Unknown);
        assert_eq!(classify(Some(true), None), FocusSafety::Unknown);
        assert_eq!(classify(None, Some(true)), FocusSafety::Unknown);
        assert_eq!(classify(None, None), FocusSafety::Unknown);
    }

    #[test]
    fn changed_or_unavailable_element_identity_fails_closed() {
        for same_element in [Some(false), None] {
            assert_eq!(
                classify_with_identity(Some(false), Some(true), same_element),
                FocusSafety::Unknown
            );
            assert_eq!(
                classify_with_identity(Some(true), Some(true), same_element),
                FocusSafety::Unknown
            );
        }
    }

    #[test]
    fn matching_element_identity_keeps_password_classification() {
        assert_eq!(
            classify_with_identity(Some(true), Some(true), Some(true)),
            FocusSafety::Password
        );
        assert_eq!(
            classify_with_identity(Some(false), Some(true), Some(true)),
            FocusSafety::NonPassword
        );
        assert_eq!(
            classify_with_identity(Some(false), Some(false), Some(true)),
            FocusSafety::Unknown
        );
    }
}

/// Minimal identity-bound reading used only by the read-only focus watcher.
/// A missing PID or failed UIA query never becomes NonPassword.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FocusSample {
    pub pid: i32,
    pub safety: FocusSafety,
}

pub fn sample_from_query(result: Result<(i32, FocusSafety), String>) -> FocusSample {
    match result {
        Ok((pid, safety)) if pid > 0 => FocusSample { pid, safety },
        _ => FocusSample {
            pid: 0,
            safety: FocusSafety::Unknown,
        },
    }
}

/// For development only: poll UIA from a dedicated MTA thread and print transitions.
/// Polling can miss quick transitions and is NOT a production authorization signal.
/// No keyboard hook, injected input, control name or text access is used.
pub fn run_watch_diagnostic() -> i32 {
    println!(
        "UIA focus watch: 20 seconds. Switch among a normal field, password field, and desktop."
    );
    println!("This is read-only; process ID and classification are the only reported values.");

    let worker = std::thread::spawn(|| {
        let until = std::time::Instant::now() + Duration::from_secs(20);
        let mut previous: Option<FocusSample> = None;
        let mut transitions = 0usize;

        while std::time::Instant::now() < until {
            #[cfg(windows)]
            let current = sample_from_query(query_focused());
            #[cfg(not(windows))]
            let current = sample_from_query(Err("Windows required".to_owned()));

            if previous != Some(current) {
                println!(
                    "focus: pid={} classification={:?}",
                    current.pid, current.safety
                );
                previous = Some(current);
                transitions += 1;
            }
            std::thread::sleep(Duration::from_millis(150));
        }
        transitions
    });

    match worker.join() {
        Ok(transitions) => {
            println!("Focus watch finished: {transitions} observed state transitions.");
            println!("No input text was read. Browsers remain blocked in normal correction mode.");
            0
        }
        Err(_) => {
            eprintln!("Focus-watch worker failed");
            1
        }
    }
}

#[cfg(test)]
mod focus_watch_tests {
    use super::*;

    #[test]
    fn missing_process_and_failed_queries_are_unknown() {
        assert_eq!(
            sample_from_query(Err("COM failure".into())),
            FocusSample {
                pid: 0,
                safety: FocusSafety::Unknown
            }
        );
        assert_eq!(
            sample_from_query(Ok((0, FocusSafety::NonPassword))),
            FocusSample {
                pid: 0,
                safety: FocusSafety::Unknown
            }
        );
    }

    #[test]
    fn valid_process_preserves_safe_and_sensitive_classifications() {
        assert_eq!(
            sample_from_query(Ok((42, FocusSafety::Password))).safety,
            FocusSafety::Password
        );
        assert_eq!(
            sample_from_query(Ok((42, FocusSafety::NonPassword))).safety,
            FocusSafety::NonPassword
        );
    }
}
