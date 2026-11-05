//! Standalone diagnostic host bundled with the desktop application.
//! stdout is reserved exclusively for binary-framed native messages.

fn main() {
    let stdin = std::io::stdin();
    let stdout = std::io::stdout();

    let mut reader = stdin.lock();
    let mut writer = stdout.lock();

    if arf_win::native_messaging::serve_one(&mut reader, &mut writer).is_err() {
        std::process::exit(1);
    }
}
