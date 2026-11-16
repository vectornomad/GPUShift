# GPUShift v0.1 — Mac + Cloud GPU Workload Switcher

**Status:** Source-code MVP. Designed for macOS 13+ with Apple Silicon; built but NOT compiler-tested in this Linux authoring environment. No cloud instance is provisioned automatically.

## Features actually implemented
- SwiftUI desktop app (profile selection, NVIDIA/AMD/Intel sections, GPU probe, AI test, Blender single-frame render, gaming stream launcher, command logs).
- Rust CLI backend, zero third-party crates, compatible with remote SSH Linux GPU workers.
- GPU vendor detection: `nvidia-smi`, `rocm-smi`/`rocminfo`, `xpu-smi`/`sycl-ls`.
- Remote PyTorch GPU availability check, with appropriate Python/PyTorch required on host.
- Upload `.blend` via SCP, render one frame on a remote Blender instance, download the output directory.
- Opens installed Moonlight client for a separately configured Sunshine host.
- SSH host-key verification enabled and batch-only login.

## Not implemented yet
- Automatic provisioning, pricing and billing, idle shutdown, provider-account integrations, model transfer/cache, latency measurements, connection health background monitoring, multiple parallel jobs, true seamless routing of macOS apps or Metal device replacement.
- Configured host/streaming server and any actual GPU are not included. AMD/Intel availability depends on your provider.
- Blender project dependencies (textures, linked assets) are NOT uploaded; pack them into the blend file first.
- Blender GPUs must be configured in the remote Blender environment; the app does not force Cycles GPU backend automatically.

## Architecture

```
macOS SwiftUI UI
   | Process (argument array; never concatenated local shell)
Rust `gpushift` CLI
   +-- SSH + vendor probe + PyTorch check
   +-- SCP + remote Blender CLI + result download
   +-- `open -a Moonlight` (external Sunshine-paired streaming host)
   +-- Profile config file -> remote NVIDIA, AMD, Intel Linux workers
Mac display and native Metal apps continue to use Apple M2.
```

## Build on your M2 MacBook

1. Install Apple Xcode command-line tools, Swift and Rust toolchain. `xcode-select --install` and install Rust from <https://rustup.rs>.
2. In Terminal at this extracted folder run `./scripts/install.sh`.
3. Edit `~/.config/gpushift/profiles.tsv` using real SSH worker credentials. Use **literal TABs**, not spaces. Replace example addresses, usernames and key paths.
4. Prepare SSH keys and trusted host keys first, e.g. `ssh -i ~/.ssh/id_ed25519 ubuntu@YOUR_GPU_HOST` (SSH host fingerprint must be verified by you). Open port 22 or a secure nonstandard SSH port as appropriate.
5. Check `~/.local/bin/gpushift list` then `~/.local/bin/gpushift probe nvidia-demo` (change the example ID to yours).
6. Launch the app at `./macos/.build/release/GPUShift` from Finder or Terminal. This is a desktop executable, not a signed distributable `.app` bundle yet.

If the macOS Swift toolchain requires an updated Xcode version or reports app packaging issues, open the `macos/Package.swift` project in Xcode; this is a Swift Package executable with a SwiftUI `@main` App.

## Profile format

`id<TAB>vendor<TAB>label<TAB>host<TAB>port<TAB>user<TAB>ssh_key_path_or_-<TAB>stream_host_or_-`

A profile maps to an **existing cloud GPU instance**. `vendor` is exactly NVIDIA, AMD, or Intel. Example entries are placeholders; no real server exists at `gpu.example.com`.

## Examples

```bash
export GPUSHIFT_PROFILES="$HOME/.config/gpushift/profiles.tsv"
gpushift doctor
gpushift list
gpushift probe nvidia-demo
gpushift ai nvidia-demo
gpushift render nvidia-demo "$HOME/Desktop/test.blend" 1 "$HOME/Desktop/gpushift-renders"
gpushift stream nvidia-demo
```

## Gaming prerequisites

1. A Windows or Linux **graphical** GPU VM with an actual working GPU driver, video encoder and supported remote streaming setup.
2. Sunshine installed/configured on that host, network route or VPN to it, proper authentication and firewall rules.
3. Moonlight installed on the Mac and paired with Sunshine once.
4. Put the game-stream host address in `stream_host`; the current command opens Moonlight, and pairing/host selection remains in Moonlight. Plain headless GPU containers generally cannot stream a normal desktop out of the box.

## Security and cost

- Prefer VPN/private mesh or an allowlisted SSH endpoint. Never expose Sunshine admin UI directly to the open internet.
- Do not hardcode provider API keys or SSH private key contents in TSV; the file stores only a private-key **path**.
- Host-key verification is enabled; do not bypass unknown host key warnings.
- VM billing begins and ends at provider-defined states. **GPUShift v0.1 never stops a VM**, so stop it manually at the provider when done. Disk and transfer fees may continue.
- Treat remote machines as untrusted: don't transfer personal data you aren't comfortable processing off-device.

## Next roadmap

**v0.2:** Provisioner plugin and safe cost budget: Runpod v2 API, verify pricing, require spending cap and explicit confirmation for creation. Stop/destroy with explicit confirmation, auto-stop timer, job-state persistence.

**v0.3:** GPU capability matrix, inference server proxy (OpenAI-compatible/local AI endpoint), remote directory sync, Blender packaged assets, job queue and file checksums.

**v0.4:** Smooth streaming handoff with Sunshine/Moonlight pairing status, quality/latency profiles, per-app launcher (not graphics-driver replacement).

**v1:** Rust daemon, native menu-bar app, on-demand sessions, policy router `local | remote`, cost/health telemetry, Keychain secrets, background notifications, tested releases.

## Reference docs

- Apple Silicon/eGPU limits: https://support.apple.com/en-ie/102363
- Blender background rendering: https://docs.blender.org/manual/en/latest/advanced/command_line/render.html
- Moonlight host setup: https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide
- Runpod v2 docs: https://docs.runpod.io/api-reference-v2/overview
