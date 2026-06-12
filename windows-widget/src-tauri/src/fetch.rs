use serde_json::Value;
use std::ffi::OsString;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::Duration;
use wait_timeout::ChildExt;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PythonCandidate {
    pub program: &'static str,
    pub prefix_args: &'static [&'static str],
}

pub fn python_candidates() -> Vec<PythonCandidate> {
    vec![
        PythonCandidate {
            program: "python",
            prefix_args: &[],
        },
        PythonCandidate {
            program: "python3",
            prefix_args: &[],
        },
        PythonCandidate {
            program: "py",
            prefix_args: &["-3"],
        },
    ]
}

pub fn probe_python() -> Option<PythonCandidate> {
    python_candidates().into_iter().find(|candidate| {
        Command::new(candidate.program)
            .args(candidate.prefix_args)
            .arg("--version")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .is_ok_and(|status| status.success())
    })
}

pub fn parse_fetch_output(success: bool, stdout: &[u8], stderr: &[u8]) -> Result<String, String> {
    if !success {
        let detail = String::from_utf8_lossy(stderr).trim().to_owned();
        return Err(if detail.is_empty() {
            "fetch_failed".into()
        } else {
            detail
        });
    }
    let raw =
        String::from_utf8(stdout.to_vec()).map_err(|_| "fetch_output_not_utf8".to_string())?;
    let raw = raw.trim();
    if raw.is_empty() {
        return Err("fetch_output_empty".into());
    }
    let value: Value =
        serde_json::from_str(raw).map_err(|_| "fetch_output_invalid_json".to_string())?;
    if value.get("schema_version").and_then(Value::as_u64) != Some(1) {
        return Err("fetch_output_wrong_schema".into());
    }
    Ok(raw.to_string())
}

pub fn fetch_usage(
    python: &PythonCandidate,
    core_dir: &Path,
    timeout: Duration,
) -> Result<String, String> {
    let script = core_dir.join("fetch_usage.py");
    let mut arguments: Vec<OsString> = python.prefix_args.iter().map(OsString::from).collect();
    arguments.push(script.into_os_string());
    let mut child = Command::new(python.program)
        .args(arguments)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|_| "no_python".to_string())?;
    let status = child
        .wait_timeout(timeout)
        .map_err(|_| "fetch_wait_failed".to_string())?;
    if status.is_none() {
        let _ = child.kill();
        let _ = child.wait();
        return Err("fetch_timed_out".into());
    }
    let output = child
        .wait_with_output()
        .map_err(|_| "fetch_output_failed".to_string())?;
    parse_fetch_output(output.status.success(), &output.stdout, &output.stderr)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_successful_contract_json() {
        let output = br#"{"schema_version":1,"claude":{},"codex":{},"kimi":{}}"#;
        assert!(parse_fetch_output(true, output, b"").is_ok());
    }

    #[test]
    fn rejects_empty_or_failed_output() {
        assert!(parse_fetch_output(true, b"", b"").is_err());
        assert!(parse_fetch_output(false, b"{}", b"failed").is_err());
    }

    #[test]
    fn python_candidates_include_windows_launcher() {
        assert!(python_candidates().iter().any(|item| item.program == "py"));
    }
}
