import SwiftUI
import UIKit

/// The developer mass test: every APK in a folder the user makes in Husk's Files folder, `DeveloperTesting`, tried in turn in this
/// run of Husk. Each APK is imported, played, watched, written down -- it runs, it started and then stopped, it never started, or
/// Husk itself went down with it (found on the next launch) -- then the session is cleared so the next APK can start. A crash still
/// resumes on the following launch. At the end the results, with each app's diagnosis and the end of its log, are one file to share.
@MainActor
final class MassTest: ObservableObject {
    static let shared = MassTest()

    /// The user's folder. Husk never makes it: its being there, with APKs in it, is what turns the test on.
    static var folder: URL { docs.appendingPathComponent("DeveloperTesting", isDirectory: true) }
    static var resultsURL: URL { docs.appendingPathComponent("DeveloperTesting Results.txt") }
    private static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private static var stateURL: URL { docs.appendingPathComponent(".husk-masstest.json") }

    /// How long a started app is watched before it counts as running, and how long one that never starts is waited for.
    private static let watchSeconds = 15.0
    private static let startTimeout = 60.0
    /// After JIT is on: a few seconds for the rest of Husk to settle before the app is played.
    private static let settleSeconds = 5.0

    struct Result: Codable {
        var file: String
        var label: String
        var package: String
        var engine: String
        var outcome: String
        var frames: UInt
        var seconds: Double
        var diagnosis: String
        var log: [String]
    }
    struct State: Codable {
        var queue: [String]
        var index: Int
        var results: [Result]
        var appIDs: [String: String]        // APK file name -> its app in the library
        var launched: Bool                  // the current one was played in the run that wrote this
        var startedAt: Date
    }

    @Published private(set) var state: State?
    @Published var shareResults = false
    @Published private(set) var status = ""

    /// One app per run of Husk: set once this run has resumed or started the test.
    private var ranThisProcess = false

    private init() { state = Self.load() }

    var active: Bool { state.map { $0.index < $0.queue.count } ?? false }

    private static let appExtensions = ["apk", "xapk", "apks", "apkm"]
    /// The apps in the folder, in name order: each APK or bundle, and each sub-folder holding an app as Google Play delivers it (a
    /// base APK and its splits). Nil if the folder is not there.
    static func apks() -> [String]? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        return names.filter { name in
            if appExtensions.contains((name as NSString).pathExtension.lowercased()) { return true }
            return !files(of: name).isEmpty
        }.sorted()
    }
    /// The files that make up one entry: the APK itself, or the APKs in its sub-folder.
    static func files(of entry: String) -> [URL] {
        let url = folder.appendingPathComponent(entry)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue { return [url] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.filter { appExtensions.contains(($0 as NSString).pathExtension.lowercased()) }.sorted().map { url.appendingPathComponent($0) }
    }

    // MARK: - Starting and stopping

    func start() {
        guard let files = Self.apks(), !files.isEmpty else { status = "请先将 APK 放入 DeveloperTesting 文件夹。"; return }
        guard !ranThisProcess else { status = "此会话已有一个测试正在运行。"; return }
        if husk_native_loaded_apk() != nil { husk_native_unload() }
        ranThisProcess = true
        state = State(queue: files, index: 0, results: [], appIDs: [:], launched: false, startedAt: Date())
        save()
        HuskLog.log("masstest", "started: \(files.count) APKs")
        runCurrent()
    }

    /// The apps the last test found not running (anything but "Runs…", and "Runs, but drew nothing"), still in the folder.
    var failures: [String] {
        guard let s = state else { return [] }
        let present = Set(Self.apks() ?? [])
        return s.results.filter { !$0.outcome.hasPrefix("Runs") || $0.outcome.hasPrefix("Runs, but drew nothing") }
                        .map(\.file).filter { present.contains($0) }
    }

    /// A new test of only those.
    func retestFailures() {
        let files = failures
        guard !files.isEmpty else { status = "没有需要重新测试的失败项目。"; return }
        guard !ranThisProcess else { status = "此会话已有一个测试正在运行。"; return }
        if husk_native_loaded_apk() != nil { husk_native_unload() }
        ranThisProcess = true
        let ids = state?.appIDs ?? [:]
        state = State(queue: files, index: 0, results: [], appIDs: ids, launched: false, startedAt: Date())
        save()
        HuskLog.log("masstest", "retesting \(files.count) failures")
        runCurrent()
    }

    func stop() {
        HuskLog.log("masstest", "stopped by the user")
        if var s = state { s.queue = Array(s.queue.prefix(s.index)); s.launched = false; state = s; save() }
        writeReport()
    }

    // MARK: - Each launch

    /// At launch, before Husk opens anything else: the previous app's fate if Husk went down with it, then the next app.
    func resume(crash: CrashReport) {
        guard !ranThisProcess, var s = state, s.index < s.queue.count else { return }
        ranThisProcess = true
        if s.launched {
            // Played in the last run and never written down: Husk did not survive it.
            let file = s.queue[s.index]
            var outcome = "Husk 关闭但未留下记录（可能达到 iOS 内存限制，或被手动划掉）"
            var diagnosis = ""
            var lines = Self.crashBlock(of: CrashReport.previousLogURL) + ["--- end of that run's log ---"] + Self.tail(of: CrashReport.previousLogURL, 60)
            if let r = crash.pending {
                outcome = "Husk 崩溃：\(r.cause.title)"
                diagnosis = r.cause.detail
                if !r.excerpt.isEmpty { lines = r.excerpt }
            }
            let native = Self.docs.appendingPathComponent("husk-native-prev.log")
            lines += ["--- native log ---"] + Self.crashBlock(of: native) + ["--- end of the native log ---"] + Self.tail(of: native, 80)
            let app = s.appIDs[file].flatMap { id in TranslationLayerStore.shared.apps.first { $0.id == id } }
            s.results.append(Result(file: file, label: app?.label ?? file, package: app?.packageName ?? "", engine: Self.engineName(app),
                                    outcome: outcome, frames: 0, seconds: 0, diagnosis: diagnosis, log: lines))
            s.index += 1
            s.launched = false
            state = s
            save()
            crash.pending = nil
            Self.discard(s.appIDs[file])
            HuskLog.log("masstest", "\(file): \(outcome)")
        }
        if active { runCurrent() } else { writeReport(); shareResults = true }
    }

    private func runCurrent() {
        guard var s = state, s.index < s.queue.count else { writeReport(); shareResults = true; return }
        let file = s.queue[s.index]
        status = "正在测试 \(s.index + 1) / \(s.queue.count)：\(file)"
        HuskLog.log("masstest", status)
        Task {
            // Taken into the library once; a later launch for the same APK (after a crash) finds it there.
            var id = s.appIDs[file]
            if id == nil || !FileManager.default.fileExists(atPath: TranslationLayer.root.appendingPathComponent(id!).path) {
                let urls = Self.files(of: file)
                id = await Task.detached(priority: .userInitiated) { TranslationLayerStore.importCopy(urls) }.value
            }
            guard let appID = id else { record(file: file, app: nil, outcome: "无法导入（不是 Husk 可读取的 APK）", frames: 0, seconds: 0); return }
            s.appIDs[file] = appID
            state = s
            save()
            TranslationLayerStore.shared.reload()
            // JIT first (this test is about the phone), then a few seconds more.
            while !Launcher.jitOn { try? await Task.sleep(nanoseconds: 500_000_000) }
            try? await Task.sleep(nanoseconds: UInt64(Self.settleSeconds * 1e9))
            guard let app = TranslationLayerStore.shared.apps.first(where: { $0.id == appID }) else {
                record(file: file, app: nil, outcome: "已导入，但未出现在游戏库中", frames: 0, seconds: 0); return
            }
            if let d = AppDiagnosis.preflight(app), d.blocksLaunch {
                record(file: file, app: app, outcome: "未启动：\(d.title)", frames: 0, seconds: 0, diagnosis: d.detail); return
            }
            var st = state!
            st.launched = true
            state = st
            save()
            HuskLog.flushNow()
            let router = Router.shared
            router.tab = .library
            router.library = [.game(appID)]
            router.autoPlay = appID
            await watch(file: file, app: app)
        }
    }

    /// What the runtime says while the app runs: started, frames, stopped.
    private func watch(file: String, app: TLApp) async {
        let t0 = Date()
        var startedAt: Date?
        while true {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let st = husk_unity_state(), frames = husk_unity_frames()
            let started = st != 0 || husk_native_loaded_apk() != nil
            if started, startedAt == nil { startedAt = Date() }
            let ran = startedAt.map { Date().timeIntervalSince($0) } ?? 0
            if st == Int32(HUSK_UNITY_FAILED) || st == Int32(HUSK_UNITY_ENDED) {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let f = husk_unity_frames()
                let outcome = st == Int32(HUSK_UNITY_FAILED) ? "无法启动"
                            : f > 30 ? "启动后停止" : "启动时崩溃"
                record(file: file, app: app, outcome: outcome, frames: f, seconds: ran)
                return
            }
            if startedAt != nil, ran >= Self.watchSeconds {
                let outcome = st == Int32(HUSK_UNITY_RUNNING)
                    ? (frames >= 60 ? "可运行" : frames > 0 ? "可运行，但绘制的帧数较少（\(frames)）" : "可运行，但未绘制画面")
                    : st == Int32(HUSK_UNITY_STARTING) ? "\(Int(ran)) 秒后仍在加载" : "运行中（此类应用无帧数统计）"
                record(file: file, app: app, outcome: outcome, frames: frames, seconds: ran)
                return
            }
            if startedAt == nil, Date().timeIntervalSince(t0) > Self.startTimeout {
                record(file: file, app: app, outcome: "始终未启动（\(Int(Self.startTimeout)) 秒）", frames: 0, seconds: 0)
                return
            }
        }
    }

    /// Writes one app's result, stops its session, and starts the next APK in this run of Husk.
    private func record(file: String, app: TLApp?, outcome: String, frames: UInt, seconds: Double, diagnosis: String? = nil) {
        guard var s = state else { return }
        var log: [String] = []
        if let c = husk_tl_attempt_log() { log = String(cString: c).components(separatedBy: "\n").suffix(150).map { String($0) }; free(c) }
        let d = diagnosis ?? AppDiagnosis.ofCurrentRun().map { "\($0.title): \($0.detail)" + ($0.evidence.map { " [\($0)]" } ?? "") } ?? ""
        s.results.append(Result(file: file, label: app?.label ?? file, package: app?.packageName ?? "", engine: Self.engineName(app),
                                outcome: outcome, frames: frames, seconds: seconds, diagnosis: d, log: log))
        s.index += 1
        s.launched = false
        state = s
        save()
        writeReport()
        Self.discard(s.appIDs[file])
        HuskLog.log("masstest", "\(file): \(outcome)")
        HuskLog.flushNow()
        CrashReport.gameEnded()
        NotificationCenter.default.post(name: TLUnityUIView.huskStopPlaying, object: nil)
        husk_native_unload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.runCurrent() }
    }

    // MARK: - Files

    /// The tested app's copy in the library, removed once its result is written: the APKs stay in DeveloperTesting, and a
    /// hundred apps imported twice over would fill the phone.
    private static func discard(_ id: String?) {
        guard let id, !id.isEmpty else { return }
        try? FileManager.default.removeItem(at: TranslationLayer.root.appendingPathComponent(id))
    }

    private static func engineName(_ app: TLApp?) -> String {
        guard let app else { return "" }
        if let w = app.report?.webKind { return "web (\(w))" }
        return app.report?.nativeEngine.map { "\($0)" } ?? "classic"
    }

    /// The crash report in a log: from the fatal signal line, its backtrace and registers (the tail alone cut them off).
    private static func crashBlock(of url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: "\n")
        guard let i = lines.lastIndex(where: { $0.contains("FATAL SIGNAL") || $0.contains("=== FATAL") || $0.contains("=== CRASH") }) else { return [] }
        return lines[max(0, i - 10)..<min(lines.count, i + 70)].map { String($0) }
    }

    private static func tail(of url: URL, _ n: Int) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n").suffix(n).map { String($0) }
    }

    /// The human-readable results: a summary table, then each app in full.
    func writeReport() {
        guard let s = state else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let commit = Bundle.main.object(forInfoDictionaryKey: "HuskBuildCommit") as? String ?? "?"
        var out = "Husk mass test -- build \(build) (\(commit)), \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)\n"
        out += "Started \(f.string(from: s.startedAt)); \(s.results.count) of \(s.queue.count) tested\n\n"
        for r in s.results { out += "\(r.outcome.padding(toLength: 44, withPad: " ", startingAt: 0))  \(r.file)  [\(r.engine)]\n" }
        for r in s.results {
            out += "\n==================== \(r.file)\n"
            out += "label: \(r.label)\npackage: \(r.package)\nengine: \(r.engine)\noutcome: \(r.outcome)\nframes: \(r.frames)  watched: \(Int(r.seconds)) s\n"
            if !r.diagnosis.isEmpty { out += "diagnosis: \(r.diagnosis)\n" }
            out += "--- log (last lines) ---\n" + r.log.joined(separator: "\n") + "\n"
        }
        try? out.write(to: Self.resultsURL, atomically: true, encoding: .utf8)
    }

    private func save() {
        guard let s = state, let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: Self.stateURL, options: .atomic)
    }
    private static func load() -> State? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }
}

/// Settings > About > Mass Test (with Developer Info on).
struct MassTestView: View {
    @ObservedObject private var test = MassTest.shared
    @State private var share = false

    var body: some View {
        let files = MassTest.apks()
        List {
            Section {
                if let files {
                    Text(files.isEmpty ? "DeveloperTesting 文件夹是空的。" : "DeveloperTesting 中有 \(files.count) 个应用。")
                } else {
                    Text("在 Husk 的文件夹（文件 > 我的 iPhone > Husk）中新建名为 DeveloperTesting 的文件夹，并把要测试的 APK 放进去：每个应用一个 APK，或每个应用一个包含基础 APK 和拆分 APK 的文件夹。")
                        .foregroundStyle(.secondary)
                }
                if let s = test.state {
                    Text(test.active ? "进行中：已完成 \(s.results.count) / \(s.queue.count)。" : "上次测试：已完成 \(s.results.count) / \(s.queue.count)。")
                }
                if !test.status.isEmpty { Text(test.status).font(.caption).foregroundStyle(.secondary) }
            } footer: {
                Text("开启 JIT 后逐个运行每个应用，观察 15 秒并记录结果，然后 Husk 关闭。重新打开 Husk 运行下一个。结束后会提供结果文件供分享。")
            }
            Section {
                if test.active {
                    Button("停止", role: .destructive) { test.stop() }
                } else {
                    Button("开始批量测试") { test.start() }.disabled((files ?? []).isEmpty)
                    if !test.failures.isEmpty {
                        Button("重新测试 \(test.failures.count) 个失败项") { test.retestFailures() }
                    }
                }
                if FileManager.default.fileExists(atPath: MassTest.resultsURL.path) {
                    Button("分享结果") { test.writeReport(); share = true }
                }
            }
        }
        .navigationTitle("批量测试")
        .huskForm()
        .sheet(isPresented: $share) { ShareSheet(items: [MassTest.resultsURL]) }
    }
}
