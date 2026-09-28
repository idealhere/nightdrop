//! Opt-in operational diagnostics for field debugging (`TODO.md` #6/#7).
//!
//! **How this differs from `devlog!`** (`node.rs`), and why both exist: `devlog!` prints
//! identity keys, invite codes, and decrypted display names, so it is compiled out of release
//! builds entirely — on Android those would land in logcat, which persists and is readable by
//! any `adb`-connected observer. That rule is not relaxed here.
//!
//! These lines are built to be safe in a release build instead: they record **what happened, not
//! who with**. Counts, outcomes, and which leg of a protocol ran — never identity keys, onion
//! addresses, invite codes, slots, secret words, or names. Anything identity-linked belongs in
//! `devlog!`, not here.
//!
//! Even so they are **off by default** and must be turned on explicitly for a debugging build
//! ([`set_enabled`], wired to `NIGHTDROP_DIAG` in the app). A normal release is silent.

use std::io::Write as _;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

static ENABLED: AtomicBool = AtomicBool::new(false);

/// Optional on-device copy of every line (see [`set_log_file`]). `None` = logcat/stderr only.
static LOG_FILE: Mutex<Option<LogFile>> = Mutex::new(None);

/// Size at which the log file rotates to `<name>.1` (replacing the previous one), so the two
/// together stay under ~2x this however long a diagnostic build runs.
const LOG_FILE_CAP: u64 = 8 * 1024 * 1024;

struct LogFile {
    path: std::path::PathBuf,
    file: std::fs::File,
    written: u64,
}

/// Turn diagnostics on/off at runtime. Off unless the app explicitly enables it.
pub fn set_enabled(on: bool) {
    ENABLED.store(on, Ordering::Relaxed);
}

/// Whether diagnostics are currently emitted.
pub fn enabled() -> bool {
    ENABLED.load(Ordering::Relaxed)
}

/// Also append every line to `path` (created if missing, appended to across launches), or stop
/// with `None`. For a **diagnostic build only** — the app calls this solely when `NIGHTDROP_DIAG`
/// is set: logcat on a phone keeps only minutes of history, so a field repro away from a PC is
/// otherwise lost before anyone can pull it.
///
/// The file gets exactly what logcat gets — the same lines, the same onion redaction, nothing
/// identity-linked — with a UTC timestamp in front. Rotates at [`LOG_FILE_CAP`].
pub fn set_log_file(path: Option<std::path::PathBuf>) -> std::io::Result<()> {
    let next = match path {
        Some(path) => {
            if let Some(dir) = path.parent() {
                std::fs::create_dir_all(dir)?;
            }
            let file = open_append(&path)?;
            let written = file.metadata().map(|m| m.len()).unwrap_or(0);
            Some(LogFile {
                path,
                file,
                written,
            })
        }
        None => None,
    };
    *LOG_FILE.lock().unwrap_or_else(|e| e.into_inner()) = next;
    Ok(())
}

fn open_append(path: &std::path::Path) -> std::io::Result<std::fs::File> {
    std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
}

/// Append one already-redacted line to the log file, if one is set. Unbuffered on purpose: a
/// force-stop or crash is often the very thing being investigated, and a buffer would lose the
/// lines leading up to it. Best-effort — a full disk must not break the app it is observing.
fn append(tag: &str, line: &str) {
    let mut guard = LOG_FILE.lock().unwrap_or_else(|e| e.into_inner());
    let Some(log) = guard.as_mut() else {
        return;
    };
    let entry = format!(
        "{} {tag} {line}\n",
        utc_timestamp(std::time::SystemTime::now())
    );
    if log.written + entry.len() as u64 > LOG_FILE_CAP {
        let mut rotated = log.path.clone().into_os_string();
        rotated.push(".1");
        let _ = std::fs::rename(&log.path, &rotated);
        match open_append(&log.path) {
            Ok(file) => {
                log.file = file;
                log.written = 0;
            }
            Err(_) => {
                *guard = None; // can't reopen: stop writing rather than fail every line
                return;
            }
        }
    }
    if log.file.write_all(entry.as_bytes()).is_ok() {
        log.written += entry.len() as u64;
    }
}

/// `YYYY-MM-DDTHH:MM:SS.mmmZ`. UTC because the core has no time-zone database; logcat's local
/// times are the offset away. Civil-from-days per Howard Hinnant's algorithm, to avoid a date
/// crate for one debug aid.
fn utc_timestamp(t: std::time::SystemTime) -> String {
    let d = t.duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
    let secs = d.as_secs();
    let (days, rem) = ((secs / 86_400) as i64, secs % 86_400);
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}.{:03}Z",
        rem / 3600,
        rem / 60 % 60,
        rem % 60,
        d.subsec_millis()
    )
}

/// Emit one diagnostic line. Prefer the [`diag!`](crate::diag) macro, which skips formatting
/// entirely when diagnostics are off.
///
/// Redacts onion addresses as a last line of defense: error strings that bubble up here (e.g. a
/// relay dial failure) can carry one in their context, and the channel's guarantee — no onion
/// addresses ever reach a release log — should be enforced here, not left to each call site.
pub fn emit(line: &str) {
    let line = redact(line);
    #[cfg(target_os = "android")]
    android::write("nd-diag", &line);
    #[cfg(not(target_os = "android"))]
    eprintln!("[nd-diag] {line}");
    append("nd-diag", &line);
}

/// Emit one line of arti's own tracing (guard/circuit/dir-download/bootstrap progress) under a
/// separate `nd-tor` tag, so field debugging of a stuck Tor bootstrap can see *why* — never linked
/// to a chat. Only reached when diagnostics are on (see [`crate::transport`] tracing install).
/// Onion addresses are still redacted defensively, and so is the WebTunnel listener secret, which
/// arti prints inside every bridge line it logs.
pub fn emit_tor(line: &str) {
    if line.is_empty() {
        return;
    }
    let line = redact(line);
    #[cfg(target_os = "android")]
    android::write("nd-tor", &line);
    #[cfg(not(target_os = "android"))]
    eprintln!("[nd-tor] {line}");
    append("nd-tor", &line);
}

/// Everything this channel must never print, removed in one place.
fn redact(s: &str) -> std::borrow::Cow<'_, str> {
    match redact_onions(s) {
        std::borrow::Cow::Borrowed(s) => redact_listener_secret(s),
        std::borrow::Cow::Owned(s) => {
            std::borrow::Cow::Owned(redact_listener_secret(&s).into_owned())
        }
    }
}

/// The argument our bridge lines carry for the WebTunnel listener (`webtunnel::socks::SECRET_ARG`,
/// spelled out because `webtunnel` is an optional dependency).
const LISTENER_SECRET_ARG: &str = "listener-secret=";

/// Replace the value of every `listener-secret=` with `<redacted>`. `apply_bridges` appends that
/// secret to each bridge line, and arti's debug output quotes whole bridge lines (guard selection,
/// bridge-descriptor downloads). It is what keeps other apps on an Android device off our loopback
/// WebTunnel proxy, so it belongs in app-private storage, not in logcat or a pullable log file.
/// Seen in a Windows debug run, 2026-09-30.
fn redact_listener_secret(s: &str) -> std::borrow::Cow<'_, str> {
    if !s.contains(LISTENER_SECRET_ARG) {
        return std::borrow::Cow::Borrowed(s);
    }
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(i) = rest.find(LISTENER_SECRET_ARG) {
        let value = i + LISTENER_SECRET_ARG.len();
        out.push_str(&rest[..value]);
        out.push_str("<redacted>");
        // The value runs to the next space, quote or bracket, the separators in arti's output.
        let end = rest[value..]
            .find(|c: char| c.is_whitespace() || matches!(c, '"' | '\'' | ']' | ')' | ','))
            .map_or(rest.len(), |n| value + n);
        rest = &rest[end..];
    }
    out.push_str(rest);
    std::borrow::Cow::Owned(out)
}

/// Replace any `<base32>.onion` label with `<onion>`. Defensive and format-agnostic: it works on
/// an arbitrary string (including one embedded in an error chain) so no call site can leak an
/// address through this channel by accident.
fn redact_onions(s: &str) -> std::borrow::Cow<'_, str> {
    let Some(_) = s.find(".onion") else {
        return std::borrow::Cow::Borrowed(s);
    };
    let is_b32 = |c: char| c.is_ascii_lowercase() || ('2'..='7').contains(&c);
    let mut out = String::with_capacity(s.len());
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < s.len() {
        if s[i..].starts_with(".onion") {
            // Drop the base32 label we just copied out, then skip the ".onion" suffix.
            while out.ends_with(is_b32) {
                out.pop();
            }
            out.push_str("<onion>");
            i += ".onion".len();
        } else {
            // Advance one UTF-8 char (diagnostic strings are ASCII, but stay correct regardless).
            let mut n = 1;
            while i + n < s.len() && (bytes[i + n] & 0xC0) == 0x80 {
                n += 1;
            }
            out.push_str(&s[i..i + n]);
            i += n;
        }
    }
    std::borrow::Cow::Owned(out)
}

/// Android needs an explicit hop to liblog: a Rust `eprintln!` goes to a stderr nobody reads,
/// so diagnostics would silently vanish on the one platform we most need them on.
#[cfg(target_os = "android")]
mod android {
    use std::ffi::CString;
    use std::os::raw::{c_char, c_int};

    const ANDROID_LOG_INFO: c_int = 4;

    #[link(name = "log")]
    extern "C" {
        fn __android_log_write(prio: c_int, tag: *const c_char, text: *const c_char) -> c_int;
    }

    pub fn write(tag: &str, line: &str) {
        // Interior NULs can't cross into C; drop the line rather than fail a debug aid.
        let (Ok(tag), Ok(text)) = (CString::new(tag), CString::new(line)) else {
            return;
        };
        // SAFETY: both pointers are NUL-terminated and live for the duration of the call.
        unsafe {
            __android_log_write(ANDROID_LOG_INFO, tag.as_ptr(), text.as_ptr());
        }
    }
}

/// Emit a diagnostic line when diagnostics are enabled (see [`crate::diag`]).
///
/// Never pass identity keys, onion addresses, invite codes, slots, secret words, or display
/// names — use `devlog!` for those, which never reaches a release build.
#[macro_export]
macro_rules! diag {
    ($($t:tt)*) => {
        if $crate::diag::enabled() {
            $crate::diag::emit(&format!($($t)*));
        }
    };
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    // `ENABLED` is process-wide; keep the two tests from racing each other.
    static SERIAL: Mutex<()> = Mutex::new(());

    #[test]
    fn diagnostics_are_off_until_asked_for() {
        let _g = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        set_enabled(false);
        assert!(!enabled(), "a normal release build must stay silent");
    }

    #[test]
    fn the_macro_does_not_evaluate_its_arguments_while_disabled() {
        let _g = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        set_enabled(false);
        // If `diag!` formatted eagerly, this would panic — proving disabled really is free, and
        // that a secret passed by mistake is never even rendered while off.
        crate::diag!("{}", panic_if_formatted());
        set_enabled(true);
        assert!(enabled());
        set_enabled(false);
    }

    fn panic_if_formatted() -> &'static str {
        panic!("diag! must not format its arguments when diagnostics are disabled");
    }

    #[test]
    fn onion_addresses_are_redacted() {
        // A real v3 onion (56 base32 chars) embedded in an error chain, with a trailing port.
        let onion = "bzcqxuxwvtmrmvprsoscnronkjf5wknfuj5ozxiq5fr6qowvnkwrwwad.onion";
        let input = format!("join: post FAILED: relay connect {onion}:9001");
        let got = redact_onions(&input);
        assert_eq!(got, "join: post FAILED: relay connect <onion>:9001");
        assert!(!got.contains(".onion"), "no onion label may survive: {got}");
    }

    #[test]
    fn listener_secret_is_redacted_wherever_arti_quotes_it() {
        // Shape of arti's bridge-descriptor line, with an onion elsewhere in the same line.
        let onion = "bzcqxuxwvtmrmvprsoscnronkjf5wknfuj5ozxiq5fr6qowvnkwrwwad.onion";
        let line = format!(
            "DEBUG tor_dirmgr::bridgedesc: starting download for \"webtunnel [2001:db8::1]:443 \
             $93807a85 url=https://example.net/p ver=0.0.3 listener-secret=0123456789abcdef\" \
             via {onion}; again listener-secret=fedcba9876543210]"
        );
        let got = redact(&line);
        assert!(!got.contains("0123456789abcdef"), "{got}");
        assert!(!got.contains("fedcba9876543210"), "{got}");
        assert!(!got.contains(".onion"), "{got}");
        assert!(
            got.contains("ver=0.0.3 listener-secret=<redacted>\" via <onion>; again listener-secret=<redacted>]"),
            "{got}"
        );
        // A secret at the very end of the line.
        assert_eq!(
            redact("x listener-secret=abc"),
            "x listener-secret=<redacted>"
        );
    }

    #[test]
    fn timestamps_are_utc_iso8601() {
        use std::time::{Duration, UNIX_EPOCH};
        assert_eq!(utc_timestamp(UNIX_EPOCH), "1970-01-01T00:00:00.000Z");
        let t = UNIX_EPOCH + Duration::from_millis(1_790_635_937_123);
        assert_eq!(utc_timestamp(t), "2026-09-28T22:52:17.123Z");
        let leap = UNIX_EPOCH + Duration::from_secs(1_709_251_199);
        assert_eq!(utc_timestamp(leap), "2024-02-29T23:59:59.000Z");
    }

    /// A fresh, empty scratch dir for one test (no tempfile dependency for a debug aid).
    fn scratch(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("nd-diag-test-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn the_log_file_gets_what_logcat_gets_and_survives_a_relaunch() {
        let _g = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scratch("file");
        let path = dir.join("sub").join("nightdrop-diag.log");
        set_log_file(Some(path.clone())).unwrap(); // creates the missing parent dirs
        set_enabled(true);
        crate::diag!("relay: drain round: {} ok", 5);
        let onion = "bzcqxuxwvtmrmvprsoscnronkjf5wknfuj5ozxiq5fr6qowvnkwrwwad.onion";
        emit_tor(&format!("circuit to {onion} built"));
        // A relaunch opens the same file again: it must append, not truncate.
        set_log_file(Some(path.clone())).unwrap();
        crate::diag!("after relaunch");
        // Unset: later lines stay out of the file.
        set_log_file(None).unwrap();
        crate::diag!("not in the file");
        set_enabled(false);

        let text = std::fs::read_to_string(&path).unwrap();
        // Other tests run in parallel and may `diag!` while this one has diagnostics on, so pick
        // out our own lines rather than expecting the file to hold nothing else.
        let ours = [
            "drain round: 5 ok",
            "circuit to",
            "after relaunch",
            "not in the file",
        ];
        let lines: Vec<&str> = text
            .lines()
            .filter(|l| ours.iter().any(|m| l.contains(m)))
            .collect();
        assert_eq!(lines.len(), 3, "{text}");
        assert!(
            lines[0].ends_with(" nd-diag relay: drain round: 5 ok"),
            "{}",
            lines[0]
        );
        assert!(
            lines[0].starts_with("20") && lines[0].as_bytes()[23] == b'Z',
            "{}",
            lines[0]
        );
        assert!(
            lines[1].ends_with(" nd-tor circuit to <onion> built"),
            "{}",
            lines[1]
        );
        assert!(
            !text.contains(".onion"),
            "an onion address reached the file: {text}"
        );
        assert!(lines[2].ends_with(" nd-diag after relaunch"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_log_file_rotates_instead_of_growing_forever() {
        let _g = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let dir = scratch("rotate");
        let path = dir.join("nightdrop-diag.log");
        set_log_file(Some(path.clone())).unwrap();
        let chunk = "x".repeat(64 * 1024);
        let lines = LOG_FILE_CAP / chunk.len() as u64 + 2; // just past one cap's worth
        for _ in 0..lines {
            emit(&chunk);
        }
        emit("newest");
        set_log_file(None).unwrap();

        let current = std::fs::metadata(&path).unwrap().len();
        let rotated = std::fs::metadata(dir.join("nightdrop-diag.log.1"))
            .unwrap()
            .len();
        assert!(
            rotated <= LOG_FILE_CAP,
            "rotated file overran the cap: {rotated}"
        );
        assert!(
            current <= LOG_FILE_CAP,
            "current file overran the cap: {current}"
        );
        let text = std::fs::read_to_string(&path).unwrap();
        assert!(
            text.trim_end().ends_with(" nd-diag newest"),
            "newest line lost in rotation"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn redaction_leaves_ordinary_lines_untouched() {
        let line = "join: opener posted to 0/1 relays";
        assert!(matches!(redact_onions(line), std::borrow::Cow::Borrowed(_)));
        assert!(matches!(redact(line), std::borrow::Cow::Borrowed(_)));
    }
}
