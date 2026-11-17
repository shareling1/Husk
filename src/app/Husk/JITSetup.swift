// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Network
import SwiftUI
import UIKit

/// How Husk gets a debugger attached. See docs/06-built-in-jit.md.
enum JITMethod: String, CaseIterable, Identifiable {
    /// StikDebug when it is installed, then TrollStore, otherwise Built-in StikJIT.
    case automatic
    case stikDebug
    case trollStore
    case jailbreak
    case builtIn

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "自动"
        case .stikDebug: return "StikDebug"
        case .trollStore: return "TrollStore"
        case .jailbreak: return "越狱（Dopamine）"
        case .builtIn: return "内置 StikJIT"
        }
    }
}

/// Where Built-in StikJIT's pairing file came from.
enum JITPairingSource: String {
    /// Made by Husk on this device (iOS 27, OnDevicePairing).
    case onDevice
    /// Imported from a file made on a computer.
    case imported
}

/// The RPPairing file Built-in StikJIT authenticates with. Lives in Documents,
/// so it is visible through Finder file sharing -- it is device-sensitive and
/// is only ever sent to Husk's own helper process.
enum JITPairingFileStore {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StikJIT", isDirectory: true)
    }
    static var url: URL { directory.appendingPathComponent("pairingFile.plist") }
    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
    private static let sourceKey = "husk.jitPairingSource"

    static var source: JITPairingSource? {
        guard exists else { return nil }
        return UserDefaults.standard.string(forKey: sourceKey).flatMap(JITPairingSource.init(rawValue:)) ?? .imported
    }

    static func data() throws -> Data { try Data(contentsOf: url) }

    static func importFile(from source: URL) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try store(try Data(contentsOf: source), source: .imported)
    }

    /// Validates an RPPairing plist and makes it the pairing file.
    static func store(_ data: Data, source: JITPairingSource) throws {
        guard !data.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any],
              let publicKey = dictionary["public_key"] as? Data, publicKey.count == 32,
              let privateKey = dictionary["private_key"] as? Data, privateKey.count == 32,
              let identifier = dictionary["identifier"] as? String, !identifier.isEmpty else {
            throw NSError(domain: "HuskJIT", code: 10,
                          userInfo: [NSLocalizedDescriptionKey:
                            "这不是远程配对文件。请参照 StikDebug 配对文件指南创建文件后重试。"])
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        UserDefaults.standard.set(source.rawValue, forKey: sourceKey)
    }
}

@MainActor
final class JITCoordinator: ObservableObject {
    static let shared = JITCoordinator()

    /// Why the built-in helper could not reach this device, read from its error.
    enum ConnectionProblem: Equatable {
        /// Nothing answered at LocalDevVPN's address: the VPN is off or not routing.
        case vpn
        /// The device closed the connection, usually because it no longer accepts
        /// this pairing (every new pairing replaces the last).
        case pairing

        init?(helperMessage: String) {
            let text = helperMessage.lowercased()
            let has = { (needles: [String]) in needles.contains(where: text.contains) }
            if has(["connectionreset", "connection reset", "device refused connection"]) {
                self = .pairing
            } else if has(["connectionrefused", "connection refused", "timedout", "timed out",
                           "networkunreachable", "network unreachable", "hostunreachable",
                           "host unreachable", "no route"]) {
                self = .vpn
            } else {
                return nil
            }
        }

        var message: String {
            switch self {
            case .vpn:
                return "Husk 无法连接到此设备。请连接 LocalDevVPN 后重试。"
            case .pairing:
                return "此设备关闭了连接，通常表示它已不再接受 Husk 的配对。请重新配对，并确认 LocalDevVPN 已连接。"
            }
        }
    }

    @Published var method: JITMethod {
        didSet { UserDefaults.standard.set(method.rawValue, forKey: "husk.jitMethod") }
    }
    @Published var showSetup = false
    @Published private(set) var connectionProblem: ConnectionProblem?
    @Published private(set) var busy = false
    @Published private(set) var status: String?
    @Published private(set) var error: String?
    @Published private(set) var txmPresent: Bool?
    /// The setup check passed for the current pairing file.
    @Published private(set) var prepared = false
    @Published private(set) var pairingSource = JITPairingFileStore.source
    /// Bumped each time the built-in helper attaches. Husk stays in the
    /// foreground for that, so nothing else tells ContentView to claim the region.
    @Published private(set) var attachGeneration = 0

    var hasPairing: Bool { pairingSource != nil }

    private init() {
        method = UserDefaults.standard.string(forKey: "husk.jitMethod")
            .flatMap(JITMethod.init(rawValue:)) ?? .automatic
    }

    var resolvedMethod: JITMethod {
        guard method == .automatic else { return method }
        if JITBootstrap.isStikDebugInstalled { return .stikDebug }
        if JITBootstrap.isTrollStoreInstalled { return .trollStore }
        if JITBootstrap.isJailbroken { return .jailbreak }
        return .builtIn
    }

    var automaticDescription: String {
        switch resolvedMethod {
        case .stikDebug: return "已安装 StikDebug，Husk 将打开它。"
        case .trollStore: return "已安装 TrollStore，Husk 将请求它启用 JIT。"
        case .jailbreak: return "检测到此设备已越狱，请在越狱工具中开启“Allow JIT in Apps”。"
        default: return "未检测到 StikDebug、TrollStore 或越狱环境，Husk 将使用内置助手。"
        }
    }

    func refreshPairingStatus() {
        pairingSource = JITPairingFileStore.source
    }

    private func log(_ line: String) { HuskLog.log("jit", line) }

    /// Get a debugger attached with whichever method applies, or open the setup
    /// walkthrough when that method is not set up yet.
    /// "Turn on JIT at launch": when Husk opens without JIT, ask the built-in StikJIT for it straight away, once per launch.
    /// Only when StikJIT can do it unattended -- it is available here and already paired -- so opening Husk never lands in
    /// the setup walkthrough by surprise.
    static let autoEnableKey = "husk.jit.autoEnable"
    private var autoTried = false

    /// A Husk TrollStore installed asks TrollStore for JIT each time it opens without it (#135), unless turned off in Settings:
    /// TrollStore attaches to the running Husk for a moment, with nothing to tap.
    static let trollStoreAutoKey = "husk.jit.trollStoreAuto"
    static var trollStoreAuto: Bool { UserDefaults.standard.object(forKey: trollStoreAutoKey) as? Bool ?? true }

    func enableAtLaunchIfAsked() {
        if !autoTried, JITBootstrap.isInstalledWithTrollStore, Self.trollStoreAuto {
            autoTried = true
            guard !JITBootstrap.ready else { return }
            log("installed by TrollStore: asking it for JIT at launch")
            method = .trollStore
            enable()
            return
        }
        guard !autoTried, UserDefaults.standard.bool(forKey: Self.autoEnableKey) else { return }
        autoTried = true
        guard !JITBootstrap.ready else { return }
        guard HuskBuiltInJIT.isAvailable, hasPairing else {
            log("JIT at launch is on, but built-in StikJIT is not available or not paired; skipped")
            return
        }
        log("turning JIT on at launch with built-in StikJIT")
        method = .builtIn
        enable()
    }

    func enable() {
        guard !JITBootstrap.ready else { return }
        error = nil
        connectionProblem = nil
        switch resolvedMethod {
        case .automatic:
            assertionFailure("Automatic must resolve to a concrete JIT method")
        case .stikDebug:
            // requestAttach() calls open() on stikjit:// and cannot report failure
            // synchronously: an unclaimed scheme fails open() silently. Wait for
            // CS_DEBUGGED so a missing StikDebug still ends in a clear message.
            if JITBootstrap.requestAttach() {
                awaitStikDebug()
            } else if JITBootstrap.requestTrollStoreAttach() {
                awaitTrollStore()
            } else {
                error = "未安装 StikDebug。请安装它，或配置内置 StikJIT。"
                showSetup = true
            }
        case .trollStore:
            if JITBootstrap.requestTrollStoreAttach() {
                awaitTrollStore()
            } else {
                error = "无法打开 TrollStore。请通过 TrollStore 安装 Husk，或选择其他方式。"
                showSetup = true
            }
        case .jailbreak:
            // Nothing to ask: a jailbreak marks an app as debugged as it opens, if it has been told to. Say what to turn on.
            error = "请在 Dopamine 设置中开启“Allow JIT in Apps”，然后重新打开 Husk。"
            showSetup = true
        case .builtIn:
            guard HuskBuiltInJIT.isAvailable, hasPairing else {
                log("built-in JIT is not set up; opening the walkthrough")
                showSetup = true
                return
            }
            enableBuiltIn()
        }
    }

    /// After TrollStore is asked: it opens Husk again and attaches to it for a moment, which marks the process as debugged. Watch for
    /// that, so the Games tab and the Library notice without waiting for another trip to the foreground, and say what to check if
    /// it never comes -- TrollStore only answers enable-jit once its URL Scheme setting is on.
    private func awaitTrollStore() {
        busy = true
        status = "正在等待 TrollStore 启用 JIT…"
        log("waiting for TrollStore's attach")
        _ = Self.waitForDebugger(timeout: 60) { [weak self] attached in
            guard let self else { return }
            busy = false
            if attached {
                status = "JIT 已开启。"
                error = nil
                attachGeneration += 1
                log("TrollStore enabled JIT")
            } else {
                status = nil
                error = "TrollStore 未启用 JIT。请在其设置中开启 URL Scheme，并确认 Husk 通过 TrollStore 安装（或签名包含 get-task-allow 权限）。"
                log("TrollStore did not enable JIT within a minute")
                showSetup = true
            }
        }
    }

    /// After StikDebug is asked to attach: open() cannot say whether it found StikDebug,
    /// so watch CS_DEBUGGED the same way awaitTrollStore does.
    private func awaitStikDebug() {
        busy = true
        status = "正在等待 StikDebug 附加…"
        log("waiting for StikDebug's attach")
        _ = Self.waitForDebugger(timeout: 60) { [weak self] attached in
            guard let self else { return }
            busy = false
            if attached {
                status = "JIT 已开启。"
                error = nil
                attachGeneration += 1
                log("StikDebug attached")
            } else {
                status = nil
                error = "StikDebug 未在一分钟内附加。请确认已安装，然后重试。"
                log("StikDebug did not attach within a minute")
                showSetup = true
            }
        }
    }

    func importPairingFile(_ source: URL) {
        do {
            try JITPairingFileStore.importFile(from: source)
            OnDevicePairing.shared.cancel()
            refreshPairingStatus()
            method = .builtIn
            prepared = false
            status = "配对文件已导入。"
            error = nil
            log("pairing file imported")
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// OnDevicePairing finished: its file becomes the pairing file and Built-in StikJIT the method.
    func storeOnDevicePairing(_ data: Data) throws {
        try JITPairingFileStore.store(data, source: .onDevice)
        refreshPairingStatus()
        method = .builtIn
        prepared = false
        status = "已在此设备上完成配对。"
        error = nil
    }

    /// Check LocalDevVPN and the Developer Disk Image, mounting it when needed.
    func prepareBuiltIn() {
        guard let pairing = builtInPairing() else { return }
        busy = true
        error = nil
        connectionProblem = nil
        status = "正在检查 LocalDevVPN 和开发者磁盘映像…"
        RemotePairingPortDiscovery.resolve { port in
            HuskBuiltInJIT.send(.prepare(pairingData: pairing, rsdPort: port)) { [weak self] result in
                guard let self else { return }
                busy = false
                switch result {
                case .success(let response):
                    txmPresent = response.txmPresent
                    prepared = response.success
                    status = response.success ? response.message : nil
                    error = response.success ? nil : helperFailure(response.message)
                    log("setup check \(response.success ? "passed" : "failed"): \(response.message)")
                case .failure(let failure):
                    prepared = false
                    status = nil
                    error = failure.localizedDescription
                }
            }
        }
    }

    func enableBuiltIn() {
        guard let pairing = builtInPairing() else { return }
        guard let script = JITBootstrap.scriptBase64 else {
            error = "此次安装缺少 Husk 的 JIT 脚本，请重新安装 Husk。"
            return
        }

        busy = true
        error = nil
        connectionProblem = nil
        status = "正在启动 Husk 的 JIT 助手…"
        log("enabling JIT with the built-in helper")
        var readiness: Timer?
        var finished = false
        let finish: (String?) -> Void = { [weak self] failure in
            guard let self, !finished else { return }
            finished = true
            readiness?.invalidate()
            busy = false
            if let failure {
                status = nil
                error = failure
                log("built-in JIT failed: \(failure)")
                showSetup = true
            } else {
                status = "JIT 已开启。"
                error = nil
                attachGeneration += 1
                log("built-in helper attached")
            }
        }

        RemotePairingPortDiscovery.resolve { port in
            HuskBuiltInJIT.send(
                .enable(targetPID: getpid(), pairingData: pairing, scriptBase64: script, rsdPort: port),
                started: { [weak self] in
                    self?.status = "正在等待助手附加…"
                    readiness = Self.waitForDebugger { attached in
                        finish(attached ? nil : "助手未在 90 秒内附加。请检查 LocalDevVPN 是否已连接，然后重试。")
                    }
                },
                completion: { [weak self] result in
                    // The helper replies once Husk detaches, or when attaching failed.
                    switch result {
                    case .success(let response):
                        self?.txmPresent = response.txmPresent
                        HuskLog.log("jit", "helper: \(response.message)")
                        if !response.success {
                            finish(self?.helperFailure(response.message) ?? response.message)
                        }
                    case .failure(let failure):
                        finish(failure.localizedDescription)
                    }
                })
        }
    }

    func resetDDI() {
        busy = true
        error = nil
        status = "正在重置开发者磁盘映像缓存…"
        HuskBuiltInJIT.send(.resetDDI) { [weak self] result in
            guard let self else { return }
            busy = false
            prepared = false
            switch result {
            case .success(let response):
                status = response.success ? response.message : nil
                error = response.success ? nil : response.message
            case .failure(let failure):
                status = nil
                error = failure.localizedDescription
            }
        }
    }

    private func builtInPairing() -> Data? {
        if let reason = HuskBuiltInJIT.unavailableReason {
            error = reason
            return nil
        }
        guard let pairing = try? JITPairingFileStore.data() else {
            error = "请先为此设备配对，或导入其配对文件。"
            return nil
        }
        return pairing
    }

    /// The helper's failure as shown: a connection problem gets its plain
    /// explanation (the helper's own message is already in the log).
    private func helperFailure(_ message: String) -> String {
        connectionProblem = ConnectionProblem(helperMessage: message)
        return connectionProblem?.message ?? message
    }

    /// Polls CS_DEBUGGED until it is set or `timeout` passes.
    private static func waitForDebugger(timeout: TimeInterval = 90,
                                        completion: @escaping (Bool) -> Void) -> Timer {
        let deadline = Date().addingTimeInterval(timeout)
        let timer = Timer(timeInterval: 0.5, repeats: true) { timer in
            if JITBootstrap.debuggedFlag {
                timer.invalidate()
                completion(true)
            } else if Date() >= deadline {
                timer.invalidate()
                completion(false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

/// LocalDevVPN, which Built-in StikJIT and StikDebug reach the device through:
/// open it to connect when it is installed, otherwise its App Store page.
enum LocalDevVPN {
    static let appStore = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044")!
    /// `enable` connects the VPN; `scheme` has LocalDevVPN return to Husk afterwards.
    static let connect = URL(string: "localdevvpn://enable?scheme=husk")!

    static var isInstalled: Bool { UIApplication.shared.canOpenURL(URL(string: "localdevvpn://")!) }
    static var actionTitle: String { isInstalled ? "连接 LocalDevVPN" : "获取 LocalDevVPN" }

    @MainActor static func open() {
        let installed = isInstalled
        HuskLog.log("jit", "LocalDevVPN \(installed ? "connect" : "app-store")")
        UIApplication.shared.open(installed ? connect : appStore)
    }
}

/// The device advertises RemotePairing on a port it picks at boot, while
/// StikJIT defaults to the old fixed 49152. Find the advertised port so
/// Built-in StikJIT keeps working after the device restarts.
enum RemotePairingPortDiscovery {
    private static let serviceType = "_remotepairing._tcp"
    private static let queue = DispatchQueue(label: "com.husk.app.remotepairing-discovery", qos: .utility)
    private static let lock = NSLock()
    private static var cachedPort: UInt16?
    private static var lastFailure: Date?

    /// Calls back on the main thread. nil means the helper should use StikJIT's
    /// default.
    static func resolve(timeout: TimeInterval = 3, completion: @escaping (UInt16?) -> Void) {
        lock.lock()
        if let cachedPort {
            lock.unlock()
            DispatchQueue.main.async { completion(cachedPort) }
            return
        }
        if let lastFailure, Date().timeIntervalSince(lastFailure) < 30 {
            lock.unlock()
            DispatchQueue.main.async { completion(nil) }
            return
        }
        lock.unlock()

        queue.async {
            let port = discover(timeout: timeout)
            lock.lock()
            if let port {
                cachedPort = port
                lastFailure = nil
            } else {
                lastFailure = Date()
            }
            lock.unlock()
            HuskLog.log("jit", "RemotePairing port "
                        + (port.map { String($0) } ?? "not found; using StikJIT's default"))
            DispatchQueue.main.async { completion(port) }
        }
    }

    private static func discover(timeout: TimeInterval) -> UInt16? {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)

        let semaphore = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var finished = false
        var resolvedPort: UInt16?
        var pendingConnection: NWConnection?

        func finish(_ port: UInt16?) {
            resultLock.lock()
            if !finished {
                finished = true
                resolvedPort = port
                semaphore.signal()
            }
            resultLock.unlock()
        }

        func hasFinished() -> Bool {
            resultLock.lock()
            defer { resultLock.unlock() }
            return finished
        }

        browser.browseResultsChangedHandler = { results, _ in
            guard !hasFinished() else { return }

            let preferred = results.first { result in
                result.interfaces.contains { $0.name == "lo0" }
            } ?? results.first
            guard let result = preferred, case .service = result.endpoint else { return }

            resultLock.lock()
            let alreadyConnecting = pendingConnection != nil
            if !alreadyConnecting {
                pendingConnection = NWConnection(to: result.endpoint, using: parameters)
            }
            let connection = pendingConnection
            resultLock.unlock()

            guard !alreadyConnecting, let connection else { return }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let remoteEndpoint = connection.currentPath?.remoteEndpoint,
                       case .hostPort(_, let port) = remoteEndpoint {
                        finish(port.rawValue)
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        browser.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled:
                finish(nil)
            default:
                break
            }
        }

        browser.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + timeout)
        browser.cancel()

        resultLock.lock()
        let connectionToCancel = pendingConnection
        resultLock.unlock()
        connectionToCancel?.cancel()

        resultLock.lock()
        defer { resultLock.unlock() }
        return resolvedPort
    }
}

