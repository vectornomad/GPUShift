import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GPUProfile: Identifiable, Hashable {
    let id: String
    let vendor: String
    let label: String
    let host: String
    let streamHost: String
}

@MainActor final class GPUShiftModel: ObservableObject {
    @AppStorage("binaryPath") var binaryPath = "" 
    @AppStorage("profilesPath") var profilesPath = ""
    @Published var profiles: [GPUProfile] = []
    @Published var selectedID: String = ""
    @Published var output: String = "GPUShift ready. Load profiles to get started."
    @Published var busy: Bool = false
    @Published var blendPath: String = ""
    @Published var renderFolder: String = ""
    @Published var frame: String = "1"
    @Published var mode: String = "AI"

    init() {
        if profilesPath.isEmpty { profilesPath = NSHomeDirectory() + "/.config/gpushift/profiles.tsv" }
        if binaryPath.isEmpty { binaryPath = NSHomeDirectory() + "/.local/bin/gpushift" }
        reload()
    }
    var selected: GPUProfile? { profiles.first(where: {$0.id == selectedID}) }
    var vendors: [String] { ["NVIDIA", "AMD", "Intel"] }
    func reload() {
        let url = URL(fileURLWithPath: (profilesPath as NSString).expandingTildeInPath)
        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            output = "No profile file found at \(url.path). Follow README setup steps."; profiles = []; return
        }
        profiles = data.split(separator: "\n").filter { !$0.hasPrefix("#") }.compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 8 else { return nil }
            return GPUProfile(id:parts[0],vendor:parts[1],label:parts[2],host:parts[3],streamHost:parts[7])
        }
        if !profiles.contains(where: {$0.id == selectedID}) { selectedID = profiles.first?.id ?? "" }
        output = "Loaded \(profiles.count) GPU profiles. No remote connection has been started."
    }
    func browseBlend() {
        let panel=NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension:"blend") ?? .data]
        panel.canChooseDirectories=false
        if panel.runModal() == .OK {blendPath = panel.url?.path ?? ""}
    }
    func browseFolder() {
        let panel=NSOpenPanel(); panel.canChooseFiles=false; panel.canChooseDirectories=true; panel.canCreateDirectories=true
        if panel.runModal() == .OK {renderFolder = panel.url?.path ?? ""}
    }
    func run(_ command: String) {
        guard let selected else { output = "Choose a profile first.";return }
        let args: [String]
        switch command {
        case "probe": args = ["probe",selected.id]
        case "ai": args = ["ai",selected.id]
        case "stream": args = ["stream",selected.id]
        case "render":
            guard !blendPath.isEmpty, !renderFolder.isEmpty, let f = UInt(frame), f > 0 else {
                output = "Select a .blend file, output folder and positive frame number."; return
            }
            args = ["render",selected.id,blendPath,String(f),renderFolder]
        default: return
        }
        busy = true
        output = "Running \(command) on \(selected.label)…\n"
        let bin = (binaryPath as NSString).expandingTildeInPath
        let config = (profilesPath as NSString).expandingTildeInPath
        Task.detached {
            let process=Process(); process.executableURL = URL(fileURLWithPath:bin); process.arguments=args
            var environment=ProcessInfo.processInfo.environment
            environment["GPUSHIFT_PROFILES"] = config
            process.environment=environment
            let out=Pipe(); let err=Pipe(); process.standardOutput=out;process.standardError=err
            do {
                try process.run()
                // Read pipes concurrently to avoid deadlocks on verbose CLI output.
                let stdoutTask=Task.detached { out.fileHandleForReading.readDataToEndOfFile() }
                let stderrTask=Task.detached { err.fileHandleForReading.readDataToEndOfFile() }
                process.waitUntilExit()
                let stdout=String(decoding:await stdoutTask.value,as:UTF8.self)
                let stderr=String(decoding:await stderrTask.value,as:UTF8.self)
                await MainActor.run {
                    self.output = stdout + (stderr.isEmpty ? "" : "\n" + stderr) + "\nExit code: \(process.terminationStatus)"
                    self.busy = false
                }
            } catch {
                await MainActor.run { self.output="Unable to start GPUShift CLI: \(error.localizedDescription)";self.busy=false }
            }
        }
    }
}

struct GPUShiftView: View {
    @StateObject private var model = GPUShiftModel()
    var body: some View {
        VStack(alignment:.leading,spacing:15) {
            HStack {
                Image(systemName:"cpu.fill").font(.title)
                VStack(alignment:.leading) {
                    Text("GPUShift").font(.title2.bold())
                    Text("Local Apple GPU + remote GPU workloads").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.busy ? "RUNNING" : "IDLE").font(.caption.weight(.semibold))
                    .padding(.horizontal,10).padding(.vertical,5)
                    .background(.quaternary,in:Capsule())
            }
            HStack {
                Label("Apple M2",systemImage:"laptopcomputer")
                Spacer()
                Text("Local display GPU · always active").font(.caption).foregroundStyle(.secondary)
            }.padding(12).background(.quaternary,in:RoundedRectangle(cornerRadius:10))
            Divider()
            HStack {
                Text("Cloud GPU profiles").font(.headline)
                Spacer()
                Button("Reload") {model.reload()}
            }
            if model.profiles.isEmpty {
                Text("No profiles configured. Add a GPU worker in profiles.tsv.").foregroundStyle(.secondary)
            } else {
                ForEach(model.vendors,id:\.self) {vendor in
                    let items=model.profiles.filter {$0.vendor==vendor}
                    if !items.isEmpty {
                        Text(vendor).font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(items) {profile in
                            Button {
                                model.selectedID=profile.id
                            } label: {
                                HStack {
                                    Image(systemName:model.selectedID==profile.id ? "largecircle.fill.circle":"circle")
                                    VStack(alignment:.leading) {
                                        Text(profile.label).fontWeight(.semibold)
                                        Text(profile.host).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }.frame(maxWidth:.infinity,alignment:.leading)
                                    .padding(9)
                                    .background(model.selectedID == profile.id ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:9))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Picker("Workload",selection:$model.mode) {
                Text("AI").tag("AI")
                Text("Blender").tag("Blender")
                Text("Gaming").tag("Gaming")
            }.pickerStyle(.segmented)
            if model.mode == "Blender" {
                HStack {Text(model.blendPath.isEmpty ? "No .blend file" : URL(fileURLWithPath:model.blendPath).lastPathComponent).lineLimit(1);Spacer();Button("Choose scene") {model.browseBlend()}}
                HStack {Text(model.renderFolder.isEmpty ? "No output folder" : model.renderFolder).lineLimit(1);Spacer();Button("Output folder") {model.browseFolder()}}
                TextField("Frame",text:$model.frame)
            }
            HStack {
                Button("Check GPU") {model.run("probe")}
                Button(model.mode == "AI" ? "Test PyTorch" : model.mode == "Blender" ? "Render frame" : "Open Moonlight") {
                    model.run(model.mode == "AI" ? "ai" : model.mode == "Blender" ? "render" : "stream")
                }.buttonStyle(.borderedProminent)
            }.disabled(model.busy || model.selected == nil)
            Text("Activity / diagnostics").font(.headline)
            ScrollView {
                Text(model.output).font(.system(.caption,design:.monospaced))
                    .frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)
            }.frame(minHeight:115,maxHeight:180).padding(10)
                .background(.black.opacity(0.06),in:RoundedRectangle(cornerRadius:9))
            DisclosureGroup("Advanced settings") {
                TextField("GPUShift CLI executable",text:$model.binaryPath)
                TextField("Profiles TSV",text:$model.profilesPath)
                Text("SSH must already be configured; cloud VMs are not automatically created or stopped in v0.1.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Remote jobs and streams only. Native macOS Metal rendering stays on Apple M2.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width:520,minHeight:620)
    }
}

@main struct GPUShiftApp: App {
    var body: some Scene {
        WindowGroup("GPUShift") { GPUShiftView() }
        .windowResizability(.contentSize)
    }
}
