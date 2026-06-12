$ErrorActionPreference = "Stop"

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
  throw "Rust/Cargo is required. Install it from https://rustup.rs/"
}
if (-not (Get-Command python -ErrorAction SilentlyContinue) -and
    -not (Get-Command py -ErrorAction SilentlyContinue)) {
  throw "Python 3 is required. Install it from https://www.python.org/"
}
if (-not (Get-Command cargo-tauri -ErrorAction SilentlyContinue)) {
  cargo install tauri-cli --version "^2"
}

Push-Location "$PSScriptRoot/src-tauri"
try {
  cargo test
  cargo tauri build
} finally {
  Pop-Location
}
