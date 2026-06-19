mod fetch;

use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

use fetch::{fetch_usage, probe_python};
use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{Emitter, Manager};
use tauri_plugin_autostart::ManagerExt;
use tauri_plugin_window_state::StateFlags;

fn core_directory_from_resource_dir(resource_dir: Option<&Path>) -> PathBuf {
    if let Some(resource_dir) = resource_dir {
        let bundled = resource_dir.join("core");
        if bundled.join("fetch_usage.py").is_file() {
            return bundled;
        }
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|path| path.parent())
        .expect("src-tauri must be nested under the repository")
        .join("core")
}

fn core_directory(app: &tauri::AppHandle) -> PathBuf {
    core_directory_from_resource_dir(app.path().resource_dir().ok().as_deref())
}

fn fetch_now(app: &tauri::AppHandle) -> Result<String, String> {
    let python = probe_python().ok_or_else(|| "no_python".to_string())?;
    fetch_usage(&python, &core_directory(app), Duration::from_secs(30))
}

#[tauri::command]
fn refresh_usage(app: tauri::AppHandle) -> Result<String, String> {
    fetch_now(&app)
}

#[tauri::command]
fn get_window_position(window: tauri::Window) -> (i32, i32) {
    let pos = window.outer_position().unwrap_or_default();
    (pos.x, pos.y)
}

#[tauri::command]
fn set_window_position(window: tauri::Window, x: i32, y: i32) {
    let _ = window.set_position(tauri::Position::Physical(tauri::PhysicalPosition { x, y }));
}

fn emit_refresh(app: tauri::AppHandle) {
    thread::spawn(move || match fetch_now(&app) {
        Ok(json) => {
            let _ = app.emit("usage", json);
        }
        Err(error) => {
            let _ = app.emit("usage-error", error);
        }
    });
}

fn setup_tray(app: &tauri::App) -> tauri::Result<()> {
    let toggle = MenuItem::with_id(app, "toggle", "显示 / 隐藏", true, None::<&str>)?;
    let refresh = MenuItem::with_id(app, "refresh", "立即刷新", true, None::<&str>)?;
    let autostart_enabled = app.autolaunch().is_enabled().unwrap_or(false);
    let autostart = CheckMenuItem::with_id(
        app,
        "autostart",
        "开机自动启动",
        true,
        autostart_enabled,
        None::<&str>,
    )?;
    let quit = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let menu = Menu::with_items(app, &[&toggle, &refresh, &autostart, &separator, &quit])?;
    let autostart_item = autostart.clone();
    let mut tray = TrayIconBuilder::new()
        .menu(&menu)
        .tooltip("AI Agent Usage")
        .on_menu_event(move |app, event| match event.id().as_ref() {
            "toggle" => {
                if let Some(window) = app.get_webview_window("main") {
                    if window.is_visible().unwrap_or(false) {
                        let _ = window.hide();
                    } else {
                        let _ = window.show();
                        let _ = window.set_focus();
                    }
                }
            }
            "refresh" => emit_refresh(app.clone()),
            "autostart" => {
                let manager = app.autolaunch();
                let enabled = manager.is_enabled().unwrap_or(false);
                let result = if enabled {
                    manager.disable()
                } else {
                    manager.enable()
                };
                if result.is_ok() {
                    let _ = autostart_item.set_checked(!enabled);
                }
            }
            "quit" => app.exit(0),
            _ => {}
        });
    if let Some(icon) = app.default_window_icon() {
        tray = tray.icon(icon.clone());
    }
    tray.build(app)?;
    Ok(())
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_autostart::Builder::new().build())
        .plugin(
            tauri_plugin_window_state::Builder::new()
                .with_state_flags(StateFlags::POSITION)
                .build(),
        )
        .invoke_handler(tauri::generate_handler![refresh_usage, get_window_position, set_window_position])
        .setup(|app| {
            setup_tray(app)?;
            if !app.autolaunch().is_enabled().unwrap_or(false) {
                let _ = app.autolaunch().enable();
            }
            let handle = app.handle().clone();
            thread::spawn(move || {
                loop {
                    thread::sleep(Duration::from_secs(60));
                    match fetch_now(&handle) {
                        Ok(json) => {
                            let _ = handle.emit("usage", json);
                        }
                        Err(error) => {
                            let _ = handle.emit("usage-error", error);
                        }
                    }
                }
            });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running AI Agent Usage Widget");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn core_directory_prefers_bundled_when_fetch_script_exists() {
        let temp = std::env::temp_dir().join("usage-widget-test");
        let core = temp.join("core");
        std::fs::create_dir_all(&core).unwrap();
        std::fs::write(core.join("fetch_usage.py"), "").unwrap();

        let result = core_directory_from_resource_dir(Some(&temp));
        assert_eq!(result, core);

        let _ = std::fs::remove_dir_all(&temp);
    }

    #[test]
    fn core_directory_falls_back_to_dev_path() {
        let result = core_directory_from_resource_dir(None);
        let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let expected = manifest.parent().unwrap().parent().unwrap().join("core");
        assert_eq!(result, expected);
    }
}
