#!/usr/bin/env python3
"""GPUShift v0.3 read-only Vast.ai CLI integration.
Applies to GPUShift v0.1 with the earlier telemetry/offline patches.
Never rents, starts, stops, or destroys instances.
"""
from pathlib import Path
import sys, shutil

root = Path(sys.argv[1]).expanduser().resolve() if len(sys.argv) > 1 else Path.cwd()
rust = root / 'backend/src/main.rs'
swift = root / 'macos/Sources/GPUShift/main.swift'
if not rust.is_file() or not swift.is_file():
    sys.exit('ERROR: Run from GPUShift root; source files not found.')
a, b = rust.read_text(), swift.read_text()
if 'fn vast_command(' in a or 'func runVast(' in b:
    sys.exit('ERROR: Vast.ai integration already present; no changes made.')
def swap(source, before, after, label):
    n=source.count(before)
    if n != 1:
        sys.exit(f'ERROR: expected one {label}, found {n}. No files changed.')
    return source.replace(before, after, 1)

rust_feature = r'''// Read-only Vast.ai discovery, delegated to the official Vast.ai CLI.
// Never pass credentials through GPUShift config or CLI arguments.
fn vast_binary() -> PathBuf {
    if let Ok(path) = env::var("VASTAI_BIN") {
        if !path.is_empty() { return PathBuf::from(path); }
    }
    if let Ok(home) = env::var("HOME") {
        let path = PathBuf::from(home).join(".local/bin/vastai");
        if path.is_file() { return path; }
    }
    for name in ["/opt/homebrew/bin/vastai", "/usr/local/bin/vastai"] {
        let path = PathBuf::from(name);
        if path.is_file() { return path; }
    }
    PathBuf::from("vastai")
}
fn vast_command(args: &[String]) -> Result<(), String> {
    let subcommand = args.get(2).map(|s| s.as_str()).unwrap_or("");
    let flags: Vec<&str> = match subcommand {
        "offers" => vec!["search", "offers", "num_gpus=1 rentable=true", "--limit", "10"],
        "instances" => vec!["show", "instances"],
        _ => return Err("Usage: gpushift vast offers | gpushift vast instances".into()),
    };
    if args.len() != 3 {
        return Err("Usage: gpushift vast offers | gpushift vast instances".into());
    }
    let status = Command::new(vast_binary()).args(flags).status()
        .map_err(|e| format!("Vast.ai CLI unavailable ({e}). Install from https://cloud.vast.ai/cli/ then run `vastai set api-key` locally."))?;
    if status.success() { Ok(()) }
    else { Err(format!("Vast.ai command exited with {status}")) }
}

'''
a=swap(a,'fn run() -> Result<(), String> {',rust_feature+'fn run() -> Result<(), String> {','Rust run()')
a=swap(a,'    let profiles = load()?;','    if a[1] == "vast" { return vast_command(&a); }\n    let profiles = load()?;','Rust profile load')
# Help may be a single escaped string literal.
a=swap(a,'gpushift doctor\\nProfiles:', 'gpushift doctor\\n  gpushift vast offers\\n  gpushift vast instances\\nProfiles:', 'Rust usage text')

swift_feature = '''  // Provider operations are read-only in this release. No cloud rental is started.
  func runVast(_ action: String) {
    guard action == "offers" || action == "instances", !busy else { return }
    busy = true
    output = action == "offers" ? "Searching Vast.ai GPU offers…" : "Fetching Vast.ai instances…"
    let bin = (binaryPath as NSString).expandingTildeInPath
    Task.detached {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: bin)
      process.arguments = ["vast", action]
      let out = Pipe()
      let err = Pipe()
      process.standardOutput = out
      process.standardError = err
      do {
        try process.run()
        let stdoutTask = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }
        let stderrTask = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }
        process.waitUntilExit()
        let stdout = String(decoding: await stdoutTask.value, as: UTF8.self)
        let stderr = String(decoding: await stderrTask.value, as: UTF8.self)
        await MainActor.run {
          self.output = stdout + (stderr.isEmpty ? "" : "\\n" + stderr)
            + "\\nExit code: \\(process.terminationStatus)"
          self.busy = false
        }
      } catch {
        await MainActor.run {
          self.output = "Unable to launch GPUShift provider command: \\(error.localizedDescription)"
          self.busy = false
        }
      }
    }
  }
'''
# Avoid accidental escaped newline confusion in generated Swift.
swift_feature=swift_feature.replace('"\\\\n"','"\\n"').replace('"\\\\nExit','"\\nExit').replace('\\\\(process.terminationStatus)', '\\(process.terminationStatus)').replace('\\\\(error.localizedDescription)','\\(error.localizedDescription)')
b=swap(b,'  func browseBlend() {',swift_feature+'  func browseBlend() {','Swift browseBlend')
needle='''      if model.profiles.isEmpty {'''
buttons='''      HStack {
        Text("Vast.ai marketplace").font(.headline)
        Spacer()
        Text("Read-only").font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Button("Find GPUs") { model.runVast("offers") }
        Button("My Instances") { model.runVast("instances") }
      }.disabled(model.busy)
      Text("Provider search does not create or charge for instances.")
        .font(.caption).foregroundStyle(.secondary)
      if model.profiles.isEmpty {'''
b=swap(b,needle,buttons,'Swift profile list')
# Backups and atomic-ish replace only after all assertions pass.
for path in [rust,swift]:
    backup=path.with_suffix(path.suffix+'.pre-vast.bak')
    if not backup.exists(): shutil.copy2(path,backup)
rust.write_text(a)
swift.write_text(b)
print('Applied read-only Vast.ai integration:')
print('  CLI: gpushift vast offers / gpushift vast instances')
print('  SwiftUI: Find GPUs / My Instances')
print('  No renting, billing, or instance mutations enabled')
