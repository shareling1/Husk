// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

// MARK: - the top of every page

/// An item's page opens on its artwork, large: the name and its platform and status as chips over the bottom of it, then the
/// one thing to do -- Play, Open, Start -- as a big button, and a row of facts (how it runs, when it was last played).
private struct PageHero<Action: View>: View {
    let item: LibraryItem
    let subtitle: String
    var facts: [(symbol: String, text: String)] = []
    @ViewBuilder var action: Action

    /// playstation.logo is iOS 16+; a missing symbol on iOS 15 can blank the chip row.
    private static var psSymbol: String {
        UIImage(systemName: "playstation.logo") != nil ? "playstation.logo" : "gamecontroller.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                ItemBackdrop(item: item, pixels: 1400, fallback: Console.card)
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom, spacing: 12) {
                        if item.artworkPath == nil {
                            ItemIcon(item: item, size: 68).shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                        }
                        Text(item.title)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                    HStack(spacing: 8) {
                        PageChip(text: item.platformShort, symbol: item.isPS4 ? Self.psSymbol : "iphone", tint: .white)
                        if let st = item.status {
                            PageChip(text: st == .plays ? "运行良好" : st.label, symbol: "checkmark.seal.fill", tint: st.color)
                        }
                    }
                }
                .padding(16)
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            action
            if !facts.isEmpty {
                HStack(alignment: .top) {
                    ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                        VStack(spacing: 6) {
                            Image(systemName: f.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Console.textDim)
                            Text(f.text).font(.system(size: 12, weight: .medium)).foregroundStyle(Console.text.opacity(0.85))
                                .multilineTextAlignment(.center).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)
            }
            if !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(Console.textDim)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A chip on an item's artwork: its platform, how it runs.
private struct PageChip: View {
    let text: String
    let symbol: String
    let tint: Color
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9).frame(height: 24)
            .background(.black.opacity(0.45), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 0.5))
    }
}

/// The page's main button.
private struct BigButton: View {
    let title: String
    let systemImage: String
    var prominent = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(prominent ? Color.white : Color.accentColor)
                .background(prominent ? Color.accentColor : Color.accentColor.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
    }
}

/// A hero that sits in a List as its first row, edge to edge within the list's margins.
private extension View {
    func heroRow() -> some View {
        listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
    }
}

private func fileBytes(_ paths: [String]) -> String {
    let total = paths.reduce(Int64(0)) { sum, p in
        sum + (((try? FileManager.default.attributesOfItem(atPath: p)[.size]) as? NSNumber)?.int64Value ?? 0)
    }
    return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
}

@MainActor private func turnOnJIT() {
    let jit = JITCoordinator.shared
    if HuskBuiltInJIT.isAvailable { jit.method = .builtIn }
    jit.enable()
}

// MARK: - a game

/// A translation-layer game: Play, its settings, what it is, and removing it.
struct GamePage: View {
    let app: TLApp
    @ObservedObject private var showcase = ShowcaseStore.shared

    @ObservedObject private var store = TranslationLayerStore.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @State private var playing = false
    @State private var confirmRemove = false
    @State private var backupFile: URL?
    @State private var savesBusy = false
    @State private var savesMessage: String?
    @State private var confirmRestore: URL?
    @State private var reporting: CompatSubject?
    /// JIT-less mode converting and signing this game's libraries before it starts
    @State private var preparing: String?
    @State private var prepareFailed: String?
    @State private var confirmQuit = false

    private var runs: Bool { app.report?.canRun == true }

    /// Another session is still in this process: Play would have to unload it, which is what made games slow and crash.
    private var blockedBy: String? {
        if Router.shared.androidStarted { return "安卓" }
        let apk = app.apks.first
        guard let loaded = husk_native_loaded_apk().map({ String(cString: $0) }), loaded != apk else { return nil }
        return Self.name(ofLoaded: loaded)
    }

    private var compatSubject: CompatSubject? {
        app.packageName.map { CompatSubject(package: $0, name: app.label, isGame: LibraryItem.game(app).isGame, iconPath: app.iconPath) }
    }

    private var preflight: AppDiagnosis? { AppDiagnosis.preflight(app) }

    /// Under Play: what runs it, how long it has been played, and when last.
    private var gameFacts: [(symbol: String, text: String)] {
        var f: [(symbol: String, text: String)] = [("cpu", app.report?.runnerName ?? "转译层")]
        let t = Playtime.seconds(LibraryItem.game(app).id)
        f.append(("gamecontroller", t > 0 ? Playtime.text(t) + " 游玩过" : "尚未游玩"))
        if let d = app.lastPlayed {
            let r = RelativeDateTimeFormatter(); r.unitsStyle = .short
            f.append(("clock", "上次游玩\n" + r.localizedString(for: d, relativeTo: Date())))
        }
        return f
    }

    /// When it was last played is in the facts already: only a warning here.
    private var subtitle: String { runs ? "" : "可能无法在此 iPhone 上运行" }

    var body: some View {
        HuskPageList {
            Section {
                PageHero(item: .game(app), subtitle: subtitle, facts: gameFacts) { primary }
                    .heroRow()
            } footer: {
                if isGeodeLauncher {
                    Text("这是 Geode 的安卓启动器。在 Husk 中，Geode 直接在 Geometry Dash 内运行：请在此处（或 Geometry Dash 设置的“模组”中）启用，然后启动 Geometry Dash，点击主菜单中的 Geode 按钮获取模组。此 APK 提供 Geode 所需的库，请保留。")
                } else if !runs {
                    Text("此 APK 不包含 Husk 可运行的 ARM 代码，因此可能无法启动。")
                }
            }

            // what the files say before it starts: a damaged APK, the wrong CPU, a missing piece, protection that refuses Husk
            if let d = preflight {
                Section {
                    AppDiagnosisCard(diagnosis: d)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }
            }
            // why it stopped last time, until it plays again
            if let d = GameStatusStore.shared.diagnosis(app.id), d != preflight {
                Section("上次运行") {
                    AppDiagnosisCard(diagnosis: d, showsEvidence: true)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }
            }

            if let compatSubject, !isGeodeLauncher {
                CompatibilitySection(subject: compatSubject, reporting: $reporting)
            }

            if !ShowcaseStore.shared.pictures(for: app.packageName).isEmpty {
                Section("截图") {
                    ShowcaseGallery(package: app.packageName)
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }
            }

            Section {
                HuskLink(value: LibraryRoute.gameSettings(app.id)) {
                    Label("游戏设置", systemImage: "slider.horizontal.3")
                }
                HuskLink(value: LibraryRoute.gameReport(app.id)) {
                    Label("技术细节", systemImage: "cpu")
                }
            }

            if !isGeodeLauncher {
                Section {
                    Button { backUp() } label: { Label("备份存档", systemImage: "square.and.arrow.up") }
                        .disabled(savesBusy || !SaveBackup.hasData(app))
                    Button { pickRestore() } label: { Label("恢复存档", systemImage: "clock.arrow.circlepath") }
                        .disabled(savesBusy || loadedNow)
                } header: {
                    Text("存档")
                } footer: {
                    if let savesMessage { Text(savesMessage) }
                    else if loadedNow { Text("\(app.label) 已在本次运行中启动过。请完全关闭 Husk 后重新打开，再恢复存档。") }
                    else { Text("备份是 \(app.label) 在 Husk 中保存的全部内容的 .zip 文件，可保存在“文件”中或移到另一台设备。") }
                }
            }

            Section("关于") {
                LabeledContent("运行方式", value: app.report?.runnerName ?? "未知")
                if let st = GameStatusStore.shared.status(app.id) {
                    LabeledContent("上次运行结果") {
                        Label(st.result.label, systemImage: st.result.symbol).foregroundStyle(st.result.color)
                    }
                }
                LabeledContent("上次游玩", value: app.lastPlayed.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "从未")
                LabeledContent("大小", value: fileBytes(app.apks))
            }

            Section {
                Button(role: .destructive) { confirmRemove = true } label: {
                    Label("移除游戏", systemImage: "trash")
                }
                // on the button: on an iPad the dialog is a popover from whatever it is attached to, and the
                // whole page's anchor put it outside the view on iPadOS 15 (#218)
                .confirmationDialog("移除 \(app.label)？", isPresented: $confirmRemove, titleVisibility: .visible) {
                    Button("移除", role: .destructive) {
                        dismiss()
                        store.remove(app)
                    }
                } message: {
                    Text("游戏及其在这里保存的所有内容都会从 Husk 中删除。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(app.label)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $playing, onDismiss: askHowItRan) { TLAttemptView(app: app) }
        .sheet(item: $reporting) { CompatReportSheet(subject: $0) }
        .sheet(item: Binding(get: { backupFile.map(IdentifiedURL.init) }, set: { backupFile = $0?.url })) { f in
            ShareSheet(items: [f.url])
        }
        .confirmationDialog("替换 \(app.label) 的存档？", isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } }),
                            titleVisibility: .visible) {
            Button("替换", role: .destructive) { if let url = confirmRestore { restore(url) } }
        } message: {
            Text("\(app.label) 现在保存的内容会被备份替换。如果想保留，请先备份。")
        }
        .onReceive(NotificationCenter.default.publisher(for: TLUnityUIView.huskStopPlaying)) { _ in playing = false }
        .alert("无 JIT 模式无法准备此游戏", isPresented: Binding(get: { prepareFailed != nil }, set: { if !$0 { prepareFailed = nil } })) {
            Button("好", role: .cancel) { }
        } message: {
            Text(prepareFailed ?? "")
        }
        .confirmationDialog("关闭 Husk？", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("关闭 Husk") {
                Router.shared.switchTo(app.id)
                CrashReport.gameEnded()
                HuskLog.flushNow()
                exit(0)
            }
        } message: {
            Text("\(blockedBy ?? "The other game") 仍在运行，每次只能运行一个游戏。Husk 将关闭；重新打开后 \(app.label) 会自动启动。")
        }
        .id(jit.attachGeneration)
        .onAppear {
            // Kept until JIT is on: this page is rebuilt when it attaches (.id above), and plays then.
            guard Router.shared.autoPlay == app.id, blockedBy == nil, Launcher.jitOn || JITLess.enabled else { return }
            Router.shared.autoPlay = nil
            play()
        }
    }

    /// Play: in JIT-less mode the game's libraries are converted and signed first (once); with Geode on, whatever it is missing
    /// (a newer release, its resources) is fetched first.
    private func play() {
        if JITLess.enabled, SigningCertificate.credentials() != nil, preparing == nil {
            preparing = "正在为无 JIT 模式做准备…"
            Task {
                do {
                    try await JITLess.prepare(apks: app.apks) { text in Task { @MainActor in preparing = text } }
                    preparing = nil
                    playPrepared()
                } catch {
                    preparing = nil
                    prepareFailed = error.localizedDescription
                }
            }
            return
        }
        playPrepared()
    }

    private func playPrepared() {
        guard TLAppSettings.load(app.id).geode, case .ready = GeodeSupport.shared.current(app) else {
            if TLAppSettings.load(app.id).geode {
                Task { await GeodeSupport.shared.prepare(app); start() }
            } else {
                start()
            }
            return
        }
        start()
    }

    /// After a session that got going: how did it run? Once per game per build, and only when it played (a crash has its own sheet).
    private func askHowItRan() {
        guard var subject = compatSubject, CompatibilityStore.shared.shouldAsk(subject.package),
              GameStatusStore.shared.status(app.id)?.result == .plays else { return }
        subject.afterPlaying = true
        Task { try? await Task.sleep(nanoseconds: 500_000_000); reporting = subject }
    }

    /// Full screen, or in a window over Husk when Multitasking says so for this app.
    private func start() {
        if app.report?.runsOnNativeRuntime == true || app.report?.webKind != nil, AppWindows.opensInWindow(app) {
            AppWindows.shared.open(app)
        } else {
            AppWindows.shared.close()
            playing = true
        }
    }

    /// This game's engine is loaded in this run of Husk, so its files may be open: no restoring under it.
    private var loadedNow: Bool {
        guard let loaded = husk_native_loaded_apk().map({ String(cString: $0) }) else { return false }
        return loaded == app.apks.first
    }

    fileprivate static func name(ofLoaded loaded: String) -> String {
        if loaded.hasPrefix("ps4:") {
            return PS4Store.shared.game(String(loaded.dropFirst(4)))?.title ?? "其他游戏"
        }
        if let other = TranslationLayerStore.shared.apps.first(where: { $0.apks.first == loaded }) {
            return other.label
        }
        return "其他游戏"
    }

    private func backUp() {
        savesBusy = true; savesMessage = nil
        let app = self.app
        Task.detached {
            let result = Result { try SaveBackup.export(app) }
            await MainActor.run {
                savesBusy = false
                switch result {
                case .success(let url): backupFile = url
                case .failure(let e): savesMessage = e.localizedDescription
                }
            }
        }
    }

    private func pickRestore() {
        HuskFilePicker.present(types: [.zip], multiple: false) { urls in
            if let url = urls.first { confirmRestore = url }
        } onFail: { savesMessage = $0 }
    }

    private func restore(_ url: URL) {
        savesBusy = true; savesMessage = nil
        let app = self.app
        Task.detached {
            let result = Result { try SaveBackup.restore(app, from: url) }
            await MainActor.run {
                savesBusy = false
                switch result {
                case .success(let n): savesMessage = "已从 \(url.lastPathComponent) 恢复 \(n) 个文件。"
                case .failure(let e): savesMessage = e.localizedDescription
                }
            }
        }
    }

    /// Geode's Android launcher, added as if it were a game: it is a whole Android app, which Husk does not run. On Husk Geode
    /// is turned on from Geometry Dash's own settings, and this APK only lends it a library.
    private var isGeodeLauncher: Bool { app.packageName == GeodeSupport.launcherPackage }
    private var geometryDash: TLApp? { store.apps.first { $0.packageName == GeodeSupport.gamePackage } }

    @ViewBuilder
    private var primary: some View {
        if isGeodeLauncher {
            if let gd = geometryDash {
                BigButton(title: TLAppSettings.load(gd.id).geode ? "已为 Geometry Dash 启用 Geode" : "为 Geometry Dash 启用 Geode",
                          systemImage: "puzzlepiece.extension.fill", prominent: !TLAppSettings.load(gd.id).geode) {
                    var s = TLAppSettings.load(gd.id)
                    s.geode = true
                    s.save(gd.id)
                    Task { await GeodeSupport.shared.prepare(gd) }
                }
            } else {
                BigButton(title: "请先添加 Geometry Dash", systemImage: "plus", prominent: false) { }.disabled(true)
            }
        } else if let preparing {
            HStack(spacing: 10) { ProgressView(); Text(preparing).foregroundStyle(.secondary).lineLimit(1) }
                .frame(maxWidth: .infinity).frame(height: 50)
        } else if blockedBy != nil {
            BigButton(title: "关闭 Husk 后游玩", systemImage: "xmark.circle", prominent: false) { confirmQuit = true }
        } else if !Launcher.jitOn && !JITLess.enabled {
            if jit.busy {
                HStack(spacing: 10) { ProgressView(); Text(jit.status ?? "正在开启 JIT…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity).frame(height: 50)
            } else {
                BigButton(title: "开启 JIT 后游玩", systemImage: "bolt.fill", action: turnOnJIT)
            }
        } else {
            BigButton(title: runs ? "开始游戏" : "尝试运行", systemImage: "play.fill", prominent: runs) { play() }
        }
    }
}

// MARK: - a PS4 game

/// A PS4 game from Documents/PS4 Games: Play, and what it is. Run by the PS4 layer (libhuskps4.dylib) on Husk's JIT.
struct PS4GamePage: View {
    let game: PS4Game
    @ObservedObject private var jit = JITCoordinator.shared
    @State private var playing = false
    @State private var confirmQuit = false

    private var item: LibraryItem { .ps4(game) }

    /// QEMU Android, or another game, still holds this process.
    private var blockedBy: String? {
        if Router.shared.androidStarted { return "安卓" }
        guard let loaded = husk_native_loaded_apk().map({ String(cString: $0) }), loaded != game.libraryID else { return nil }
        return GamePage.name(ofLoaded: loaded)
    }

    private func playPS4() {
        playing = true
    }

    /// The same facts as an Android game's: version, how long it has been played, and when last.
    private var facts: [(symbol: String, text: String)] {
        var f: [(symbol: String, text: String)] = [("cpu", "PS4 转译层" + (game.version.map { "\nv\($0)" } ?? ""))]
        let t = Playtime.seconds(item.id)
        f.append(("gamecontroller", t > 0 ? Playtime.text(t) + " 游玩过" : "尚未游玩"))
        if let d = game.lastPlayed {
            let r = RelativeDateTimeFormatter(); r.unitsStyle = .short
            f.append(("clock", "上次游玩\n" + r.localizedString(for: d, relativeTo: Date())))
        }
        return f
    }

    var body: some View {
        HuskPageList {
            PageHero(item: item, subtitle: "", facts: facts) { primary }
                .heroRow()
            if !PS4Store.available {
                Section {
                    Text(PS4Store.moduleURL == nil
                         ? "此版本的 Husk 不包含 PS4 层。"
                         : "PS4 游戏需要 iOS 17.4 或更高版本。")
                        .foregroundStyle(.secondary)
                }
            }
            Section("关于") {
                LabeledContent("运行方式", value: "Husk 的 PS4 转译层")
                LabeledContent("游戏 ID", value: game.titleID)
                if let v = game.version { LabeledContent("版本", value: v) }
                LabeledContent("上次游玩", value: game.lastPlayed.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "从未")
                LabeledContent("文件夹", value: "PS4 Games/" + game.folder.lastPathComponent)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $playing) { PS4PlayView(game: game) }
        .confirmationDialog("关闭 Husk？", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("关闭 Husk") {
                Router.shared.switchTo(game.libraryID)
                CrashReport.gameEnded()
                HuskLog.flushNow()
                exit(0)
            }
        } message: {
            Text("\(blockedBy ?? "The other game") 仍在运行，每次只能运行一个游戏。Husk 将关闭；重新打开后 \(game.title) 会自动启动。")
        }
        .id(jit.attachGeneration)
        .onAppear {
            guard Router.shared.autoPlay == game.libraryID, Launcher.jitOn, blockedBy == nil, PS4Store.available else { return }
            Router.shared.autoPlay = nil
            playPS4()
        }
    }

    @ViewBuilder
    private var primary: some View {
        if !PS4Store.available {
            BigButton(title: "无法在此游玩", systemImage: "xmark.octagon", prominent: false) { }.disabled(true)
        } else if blockedBy != nil {
            BigButton(title: "关闭 Husk 后游玩", systemImage: "xmark.circle", prominent: false) { confirmQuit = true }
        } else if !Launcher.jitOn {
            if jit.busy {
                HStack(spacing: 10) { ProgressView(); Text(jit.status ?? "正在开启 JIT…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity).frame(height: 50)
            } else {
                BigButton(title: "开启 JIT 后游玩", systemImage: "bolt.fill", action: turnOnJIT)
            }
        } else {
            BigButton(title: "开始游戏", systemImage: "play.fill") { playPS4() }
        }
    }
}

// MARK: - an app inside Android

/// An app installed in Android: Open (starting Android first when it is not running), what it is, and its files.
struct AndroidAppPage: View {
    let app: AndroidHost.Package
    @ObservedObject private var showcase = ShowcaseStore.shared

    @ObservedObject private var host = AndroidHost.shared
    @ObservedObject private var guest = GuestImage.shared
    @ObservedObject private var runner = QemuRunner.shared
    @ObservedObject private var router = Router.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmUninstall = false

    private var live: AndroidHost.Package { host.packages.first { $0.name == app.name } ?? app }
    private var canOpen: Bool { host.isReady && host.busy == nil }
    private var item: LibraryItem { .app(live) }

    var body: some View {
        HuskPageList {
            Section {
                PageHero(item: item, subtitle: item.usedText ?? "在安卓中运行") { primary }
                    .heroRow()
            } footer: {
                if router.pendingAndroidLaunch == app.name, !host.isReady {
                    Text("安卓启动后，\(live.label) 会自动打开。")
                }
            }

            if !ShowcaseStore.shared.pictures(for: app.name).isEmpty {
                Section("截图") {
                    ShowcaseGallery(package: app.name)
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }
            }

            Section("关于") {
                LabeledContent("版本", value: live.version ?? "—")
                LabeledContent("大小", value: live.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
                LabeledContent("包名", value: live.name)
                if let b = live.bitness { LabeledContent("处理器架构", value: b) }
            }

            Section {
                Button { router.openFiles(at: "/sdcard/Android/data/\(app.name)") } label: {
                    Label("在“文件”中打开", systemImage: "folder")
                }
                .disabled(!canOpen)
                Button { appInfo() } label: {
                    Label("安卓应用信息", systemImage: "info.circle")
                }
                .disabled(!canOpen)
                Button { UIPasteboard.general.string = app.name } label: {
                    Label("复制包名", systemImage: "doc.on.doc")
                }
            }

            Section {
                Button(role: .destructive) { confirmUninstall = true } label: {
                    Label("卸载", systemImage: "trash")
                }
                .disabled(!canOpen)
                .confirmationDialog("卸载 \(live.label)？", isPresented: $confirmUninstall, titleVisibility: .visible) {
                    Button("卸载", role: .destructive) {
                        host.uninstall(app.name)
                        dismiss()
                    }
                } message: {
                    Text("它的数据会一起删除。")
                }
            } footer: {
                if !canOpen { Text("启动安卓以卸载或查看应用内容。") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(live.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var primary: some View {
        if canOpen {
            BigButton(title: "打开", systemImage: "play.fill") {
                host.launch(app.name) { router.openGuest() }
            }
        } else if router.androidStarted {
            VStack(spacing: 10) {
                BigButton(title: "正在启动安卓…", systemImage: "hourglass", prominent: false) { }
                    .disabled(true)
                if runner.bootProgress > 0 { ProgressView(value: Double(runner.bootProgress), total: 100) }
            }
        } else if guest.state == .ready {
            BigButton(title: Launcher.jitOn ? "启动安卓并打开" : "开启 JIT", systemImage: Launcher.jitOn ? "play.fill" : "bolt.fill") {
                if Launcher.jitOn { router.pendingAndroidLaunch = app.name }
                router.startAndroid()
            }
        } else {
            HuskLink(value: LibraryRoute.androidSystem) {
                Label("请先安装安卓", systemImage: "arrow.down.circle")
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(CardButtonStyle())
        }
    }

    /// Android's own page for the app: permissions, storage, force stop.
    private func appInfo() {
        let pkg = app.name
        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? GuestBridge.shared.shell("am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:\(pkg)", timeout: 30)
        }
        router.openGuest()
    }
}

// MARK: - Android itself

/// The whole Android system, as an app of its own: get it, start it, open it, and its settings.
struct AndroidSystemPage: View {
    @ObservedObject private var guest = GuestImage.shared
    @ObservedObject private var runner = QemuRunner.shared
    @ObservedObject private var host = AndroidHost.shared
    @ObservedObject private var router = Router.shared
    @ObservedObject private var jit = JITCoordinator.shared

    private var running: Bool { router.androidStarted }

    var body: some View {
        HuskPageList {
            Section {
                PageHero(item: .android, subtitle: status) {
                    VStack(spacing: 10) {
                        primary
                        if let progress { ProgressView(value: progress) }
                    }
                }
                .heroRow()
            } footer: {
                if let note { Text(note) }
            }

            if host.isReady {
                Section {
                    Button { router.openFiles(at: FilesTab.root) } label: { Label("文件", systemImage: "folder") }
                    Button { runner.saveState(reason: "asked from the Android page") } label: {
                        Label(runner.isSavingState ? "正在保存…" : "立即保存安卓", systemImage: "externaldrive.badge.checkmark")
                    }
                    .disabled(runner.isSavingState)
                } footer: {
                    Text("保存会让安卓保持原样，下次启动可跳过开机过程。")
                }
            }

            Section("设置") {
                NavigationLink { PerformanceSettings() } label: { Label("性能", systemImage: "speedometer") }
                NavigationLink { InputSettings() } label: { Label("输入", systemImage: "hand.tap") }
                NavigationLink { NetworkSettings() } label: { Label("网络", systemImage: "globe") }
                NavigationLink { SavedMachineSettings() } label: { Label("保存的机器", systemImage: "externaldrive") }
            }

        }
        .listStyle(.insetGrouped)
        .navigationTitle("安卓")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.2), value: status)
    }

    private var status: String {
        if running {
            if host.isReady { return "运行中" }
            return runner.setupMessage ?? (runner.bootProgress > 0 ? "正在启动 · \(runner.bootProgress)%" : "正在开始…")
        }
        switch guest.state {
        case .missing: return "尚未下载"
        case .downloading(_, let received, let total):
            return "正在下载 · \(bytes(received)) / \(total > 0 ? bytes(total) : "…")"
        case .installing: return "正在安装…"
        case .failed: return "出现问题"
        case .ready: return Launcher.jitOn ? "可以启动" : "需要开启 JIT 才能启动"
        }
    }

    private var progress: Double? {
        if running, !host.isReady, runner.bootProgress > 0 { return Double(runner.bootProgress) / 100 }
        if !running, case .downloading(let p, _, _) = guest.state { return p }
        return nil
    }

    private var note: String? {
        guard !running else { return nil }
        switch guest.state {
        case .missing: return "Husk 的安卓运行环境约为 760 MB，安装完成后将继续获取安卓系统本身。"
        case .failed(let message): return message
        default: return nil
        }
    }

    @ViewBuilder
    private var primary: some View {
        if running {
            if host.isReady {
                BigButton(title: "打开安卓", systemImage: "play.fill") { open() }
            } else {
                BigButton(title: "查看启动过程", systemImage: "eye", prominent: false) { open() }
            }
        } else {
            switch guest.state {
            case .missing:
                BigButton(title: "下载安卓", systemImage: "arrow.down.circle") {
                    // Claim the JIT region before the download: it takes a while, and StikDebug lets go by the end of it.
                    JITBootstrap.prewarm()
                    guest.download()
                }
            case .downloading:
                BigButton(title: "取消下载", systemImage: "xmark", prominent: false) { guest.cancel() }
            case .installing:
                ProgressView().frame(height: 50)
            case .failed:
                BigButton(title: "重试", systemImage: "arrow.clockwise") { JITBootstrap.prewarm(); guest.download() }
            case .ready:
                if jit.busy {
                    HStack(spacing: 10) { ProgressView(); Text(jit.status ?? "正在开启 JIT…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity).frame(height: 50)
                } else {
                    BigButton(title: Launcher.jitOn ? "启动安卓" : "开启 JIT", systemImage: Launcher.jitOn ? "power" : "bolt.fill") {
                        router.startAndroid()
                    }
                }
            }
        }
    }

    private func open() {
        UserDefaults.standard.set(Date(), forKey: "husk.android.lastOpened")
        router.openGuest()
    }

    private func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
}

/// A URL that a sheet can be presented for.
struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.path }
}
