import Foundation
import AppKit
import ServiceManagement

func string(_ value: Any?) -> String { value as? String ?? "" }
func number(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }
func strings(_ value: Any?) -> [String] { value as? [String] ?? [] }
func object(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }
func objects(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }

struct Memory: Identifiable {
    let raw: [String: Any]
    var id: String { string(raw["key"]) }
    var kind: String { string(raw["kind"]) }
    var numericID: Int { number(raw["id"]) }
    var title: String { string(raw["display_title"]) }
    var project: String { string(raw["project"]) }
    var source: String { string(raw["source"]) }
    var type: String { kind == "summary" ? "summary" : string(raw["type"]) }
    var preview: String { string(raw["narrative"]).isEmpty ? string(raw["learned"]) : string(raw["narrative"]) }
    var date: Date { Date(timeIntervalSince1970: Double(number(raw["created_at_epoch"])) / 1000) }
}

enum Bridge {
    static var demo: Bool { CommandLine.arguments.contains("--demo") }
    static var script: URL { Bundle.main.resourceURL!.appendingPathComponent("atlas.py") }
    static func run(_ request: [String: Any]) async throws -> Any {
        try await Task.detached(priority: .userInitiated) {
            let process = Process(), input = Pipe(), output = Pipe()
            let candidates = ["/opt/homebrew/opt/python@3.13/libexec/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/opt/python@3.13/libexec/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            process.executableURL = URL(fileURLWithPath: candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/python3")
            process.arguments = [script.path] + (demo ? ["--demo"] : [])
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\(NSHomeDirectory())/.bun/bin:\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["CLAUDE_MEM_INTERNAL"] = "1"
            process.environment = env
            process.standardInput = input; process.standardOutput = output
            // Write stderr to a private temporary file rather than risk filling a second pipe.
            let log = FileManager.default.temporaryDirectory.appendingPathComponent("memory-atlas-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let logHandle = try FileHandle(forWritingTo: log)
            process.standardError = logHandle
            defer { try? logHandle.close(); try? FileManager.default.removeItem(at: log) }
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: request))
            try input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            guard !data.isEmpty else { throw NSError(domain: "MemoryAtlas", code: 3, userInfo: [NSLocalizedDescriptionKey: "Python could not run the local bridge. Install Python 3.9 or newer and relaunch Atlas."]) }
            let decoded = try JSONSerialization.jsonObject(with: data)
            if let message = object(decoded)["error"] as? String { throw NSError(domain: "MemoryAtlas", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
            if process.terminationStatus != 0 { throw NSError(domain: "MemoryAtlas", code: 2, userInfo: [NSLocalizedDescriptionKey: "The local memory operation failed."]) }
            return decoded
        }.value
    }
}

@MainActor final class AtlasModel: ObservableObject {
    @Published var route = "Overview"
    @Published var records: [Memory] = []
    @Published var selected: Memory?
    @Published var info: [String: Any] = [:]
    @Published var config: [String: Any] = [:]
    @Published var graph: [String: Any] = [:]
    @Published var project = ""
    @Published var query = ""
    @Published var source = ""
    @Published var kind = ""
    @Published var days = 0
    @Published var busy = false
    @Published var loading = false
    @Published var message = ""
    @Published var error: String?
    @Published var hasMore = true
    @Published var lastUpdated: Date?
    @Published var loginEnabled = false
    private var refreshing = false
    private var timer: Timer?
    private var searchTask: Task<Void, Never>?

    var health: [String: Any] { object(info["health"]) }
    var ai: [String: Any] { object(health["ai"]) }
    var counts: [String: Any] { object(info["counts"]) }
    var projects: [[String: Any]] { objects(info["projects"]) }
    var online: Bool { string(health["status"]) == "ok" }
    var filters: [String: Any] { ["project": project, "query": query, "source": source, "kind": kind, "days": days] }
    var pending: [[String: Any]] { objects(info["pending"]) }

    init() {
        loginEnabled = !Bridge.demo && SMAppService.mainApp.status == .enabled
        if CommandLine.arguments.contains("--render-docs") { return }
        Task { await refresh(); await loadSettings() }
        // ponytail: refresh every 12 seconds; SSE can replace polling if latency becomes material.
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let self, !self.busy else { return }; await self.refresh() }
        }
    }
    func refresh() async {
        guard !refreshing, !busy else { return }; refreshing = true
        defer { refreshing = false }
        do {
            info = object(try await Bridge.run(["op": "info"]))
            lastUpdated = Date()
            if route == "Memories" { await loadMemories() }
            if route == "Knowledge Graph" { await loadGraph() }
        } catch { self.error = error.localizedDescription }
    }
    func filterChanged() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await loadMemories(); if route == "Knowledge Graph" { await loadGraph() }
        }
    }
    func loadMemories(more: Bool = false) async {
        guard !busy else { return }; loading = true
        defer { loading = false }
        do {
            var args = filters; args["op"] = "list"; args["offset"] = more ? records.count : 0; args["limit"] = 100
            let rows = objects(try await Bridge.run(args)).map { Memory(raw: $0) }
            guard NSDictionary(dictionary: filters).isEqual(to: args.filter { !["op","offset","limit"].contains($0.key) }) else { return }
            if more { records += rows } else { records = rows }
            hasMore = rows.count == 100
        } catch { self.error = error.localizedDescription }
    }
    func select(_ memory: Memory) {
        selected = memory
        Task {
            do { let detail = Memory(raw: object(try await Bridge.run(["op":"detail","kind":memory.kind,"id":memory.numericID]))); if selected?.id == memory.id { selected = detail } }
            catch { self.error = error.localizedDescription }
        }
    }
    func selectKey(_ key: String) {
        if key.hasPrefix("project:") { project = String(key.dropFirst(8)); Task { await loadGraph() }; return }
        let parts = key.split(separator: ":")
        guard parts.count == 2, let id = Int(parts[1]) else { return }
        Task {
            do { selected = Memory(raw: object(try await Bridge.run(["op":"detail","kind":String(parts[0]),"id":id]))); route = "Memories"; await loadMemories() }
            catch { self.error = error.localizedDescription }
        }
    }
    func loadGraph() async {
        do { var args=filters;args["op"]="graph";graph=object(try await Bridge.run(args)) }
        catch { self.error=error.localizedDescription }
    }
    func loadSettings() async {
        do { let result=object(try await Bridge.run(["op":"settings"])); config=object(result["settings"]).isEmpty ? result : object(result["settings"]) }
        catch { self.error=error.localizedDescription }
    }
    @discardableResult func operation(_ args: [String: Any]) async -> Bool {
        guard !busy else { return false }; busy=true;message=""
        do {
            let result=object(try await Bridge.run(args));message=string(result["message"]);if message.isEmpty {message="Saved successfully"}
            busy=false;await refresh();return true
        } catch { busy=false;self.error=error.localizedDescription;await refresh();return false }
    }
    func export(_ format: String, filtered: Bool) {
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.canCreateDirectories=true;panel.prompt="Export here";panel.message="Choose a folder for a new Memory Atlas export."
        guard panel.runModal() == .OK, let url=panel.url else{return}
        Task {
            var args=filtered ? filters : [:];args["op"]="export";args["format"]=format;args["destination"]=url.path
            busy=true
            do { let result=object(try await Bridge.run(args));message=string(result["message"]);NSWorkspace.shared.open(URL(fileURLWithPath:string(result["path"]))) }
            catch {self.error=error.localizedDescription}
            busy=false
        }
    }
    func launchAtLogin(_ enabled: Bool) {
        guard !Bridge.demo else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled=SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { SMAppService.openSystemSettingsLoginItems();message="Enable Memory Atlas in Login Items to finish startup registration." }
        } catch {self.error=error.localizedDescription}
    }
    func signIn(_ provider: String) {
        guard !Bridge.demo else { message="Demo mode does not connect an account.";return }
        let name=provider == "codex" ? "codex" : "claude"
        let candidates=["/opt/homebrew/bin/\(name)","\(NSHomeDirectory())/.local/bin/\(name)","/usr/local/bin/\(name)"]
        guard let path=candidates.first(where:{FileManager.default.isExecutableFile(atPath:$0)}) else {error="\(name) CLI is not installed.";return}
        let command="\"\(path)\" \(name == "codex" ? "login" : "auth login")"
        let escaped=command.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")
        let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/osascript");p.arguments=["-e","tell application \"Terminal\" to do script \"\(escaped)\""]
        do {try p.run()}catch{self.error=error.localizedDescription}
    }
}
