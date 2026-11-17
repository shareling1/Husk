// SPDX-License-Identifier: GPL-2.0-or-later
import Darwin
import SwiftUI
import UniformTypeIdentifiers
import os

/// Settings, as the iOS Settings app lays them out: a card for the app up top, then groups of rows that each
/// push a page of their own. What belongs to the app, what belongs to the emulator, and what the thing is.
struct SettingsTab: View {
    @AppStorage(AppWindows.defaultKey) private var multitask = false
    @AppStorage(CompatibilityStore.askKey) private var askCompat = true
    @ObservedObject private var account = Account.shared

    var body: some View {
        NavigationStack {
            HuskPageList {
                Section {
                    Button { Router.shared.showProfile = true } label: { accountCard }
                        .foregroundStyle(.primary)
                } footer: {
                    if !account.signedIn {
                        Text("Husk 账号可在本机和 itslevii.dev 之间保存个人资料、游玩时长与成就。")
                    }
                }

                Section("JIT") {
                    row(JITSettings(), "bolt.fill", .yellow, "JIT 与侧载", "已内置 StikJIT——推荐方式")
                    row(JITLessSettings(), "bolt.slash.fill", .mint, "无 JIT 游玩", "无需调试器")
                }

                Section("通用") {
                    row(DiscoverView(), "sparkle.magnifyingglass", .mint, "发现", "从 F-Droid 和其他软件源查找应用")
                    row(LibrarySettings(), "square.grid.2x2.fill", .blue, "游戏库", "你的应用及其图标")
                    row(PerformanceSettings(), "speedometer", .orange, "性能", "渲染器与声音")
                    row(AppearanceSettings(), "paintbrush.fill", .pink, "外观", "浅色或深色、主题色与应用图标")
                    row(FontSettings(), "textformat", .indigo, "字体", "中文、日文和韩文字体")
                    row(FAQTab(), "questionmark.circle.fill", .teal, "帮助", "常见问题解答")
                    row(AboutSettings(), "info.circle.fill", .gray, "关于 Husk", "版本 \(Bundle.main.version) · \(Bundle.main.commit)")
                }

                Section {
                    Toggle(isOn: $multitask) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("在窗口中打开应用")
                                Text("应用运行时继续使用 Husk").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        } icon: {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.purple.huskGradient)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: "macwindow.on.rectangle")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                        }
                    }
                } header: {
                    Text("多任务")
                } footer: {
                    Text("应用和游戏可在浮动窗口中运行，支持移动、缩放并最小化至程序坞，类似 LiveContainer 的多任务功能。每个应用都可在自身设置中覆盖此选项。")
                }

                Section {
                    Toggle(isOn: $askCompat) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("询问游戏运行情况")
                                Text("游玩之后，每个游戏每次更新一次").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        } icon: {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.green.huskGradient)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: "list.bullet.clipboard")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                        }
                    }
                    Link(destination: CompatibilityStore.site) {
                        Label("兼容性列表", systemImage: "safari")
                    }
                } header: {
                    Text("兼容性")
                } footer: {
                    Text("游戏页面与商店会显示 itslevii.dev 上大家的运行反馈。你提交的报告会包含设备、iOS 版本、Husk 版本与 JIT 方式。")
                }

                Section {
                    row(AndroidSystemPage(), "apps.iphone", AndroidMark.green, "安卓", "实验功能：完整安卓模拟器")
                    row(InputSettings(), "hand.tap.fill", .indigo, "输入", "屏幕、触控与键盘")
                    row(NetworkSettings(), "globe", .green, "网络", "网络与已保存的会话")
                    row(SavedMachineSettings(), "externaldrive.fill", .teal, "保存的机器", "快照与自动保存")
                } header: {
                    Text("安卓模拟器")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
        }
    }

    /// The top of Settings, as iOS puts the Apple Account there: the Husk account (or the way to sign in), and which Husk this is.
    private var accountCard: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                if account.signedIn { AccountAvatar(size: 60) } else { HuskMark(size: 60) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(account.signedIn ? (account.user?.displayName ?? "Husk 账号") : "登录")
                    .font(.title3.weight(.semibold))
                Text(account.signedIn ? "@" + (account.user?.username ?? "") : "个人资料、游玩时长与成就")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Husk \(Bundle.main.version) · \(Bundle.main.commit)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func row<D: View>(_ destination: D, _ icon: String, _ tint: Color,
                              _ title: String, _ subtitle: String) -> some View {
        NavigationLink { destination } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } icon: {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.huskGradient)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                    }
            }
        }
    }
}

/// A Form, as the system draws one.
private struct HuskFormStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func huskForm() -> some View { modifier(HuskFormStyle()) }
}

// MARK: - Library

struct LibrarySettings: View {
    @ObservedObject private var host = AndroidHost.shared
    @State private var working = false

    var body: some View {
        HuskForm {
            Section {
                DetailRow(label: "应用", value: "\(host.packages.count)", mono: false)
                DetailRow(label: "包含图标",
                          value: "\(host.packages.filter { $0.iconPath != nil }.count)",
                          mono: false)
            } footer: {
                Text("列表会保存到磁盘，因此安卓尚未启动完成时就能显示。")
            }

            Section {
                Button {
                    working = true
                    Task { await host.refreshPackages(); working = false }
                } label: {
                    Label(working ? "正在刷新…" : "从安卓刷新",
                          systemImage: "arrow.clockwise")
                }
                .disabled(working || !host.isReady)

                Button {
                    AndroidHost.forgetIcons()
                    working = true
                    Task { await host.refreshPackages(); working = false }
                } label: {
                    Label("重新获取图标", systemImage: "photo.on.rectangle")
                }
                .disabled(working || !host.isReady)
            } footer: {
                Text("名称和图标来自安卓启动器。重新获取会清除 Husk 的缓存并再次请求。")
            }
        }
        .huskForm()
        .navigationTitle("游戏库")
    }
}

// MARK: - Fonts

/// Chinese, Japanese and Korean fonts bundled offline in this Chinese edition. Download fallback for other builds. Apps
/// on the translation layer find them where Android keeps them, through fonts.xml, which already names the file.
@MainActor
final class CJKFonts: ObservableObject {
    static let shared = CJKFonts()
    static let fileName = "NotoSansCJK-Regular.ttc"
    static let source = URL(string: "https://raw.githubusercontent.com/notofonts/noto-cjk/165c01b46ea533872e002e0785ff17e44f6d97d8/Sans/OTC/NotoSansCJK-Regular.ttc")!
    nonisolated static var bundledFont: URL? {
        Bundle.main.url(forResource: "NotoSansCJK-Regular", withExtension: "ttc")
    }
    nonisolated static var isBundled: Bool { bundledFont != nil }
    nonisolated static var directory: URL {
        if let font = bundledFont { return font.deletingLastPathComponent() }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fonts", isDirectory: true)
    }
    nonisolated static var installed: Bool { FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path) }

    @Published private(set) var isInstalled = CJKFonts.installed
    @Published private(set) var downloading = false
    @Published private(set) var failure: String?

    func download() {
        guard !Self.isBundled, !downloading else { return }
        downloading = true
        failure = nil
        Task {
            do {
                let (temp, response) = try await URLSession.shared.download(from: Self.source)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                let dest = Self.directory.appendingPathComponent(Self.fileName)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: temp, to: dest)
                HuskLog.log("fonts", "CJK fonts installed at \(dest.path)")
                isInstalled = true
            } catch {
                failure = "下载失败：\(error.localizedDescription)"
                HuskLog.log("fonts", "CJK font download failed: \(error.localizedDescription)")
            }
            downloading = false
        }
    }

    func remove() {
        guard !Self.isBundled else { return }
        try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(Self.fileName))
        isInstalled = Self.installed
    }
}

struct FontSettings: View {
    @ObservedObject private var fonts = CJKFonts.shared

    var body: some View {
        HuskForm {
            Section {
                if CJKFonts.isBundled {
                    Label("已内置 · 无需下载", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("字体随安装包提供，离线可用，无需额外安装。").font(.caption).foregroundStyle(.secondary)
                } else if fonts.isInstalled {
                    Label("已安装", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button(role: .destructive) { fonts.remove() } label: { Label("移除", systemImage: "trash") }
                } else {
                    Button { fonts.download() } label: {
                        Label(fonts.downloading ? "正在下载…" : "下载（19.5 MB）", systemImage: "arrow.down.circle")
                    }
                    .disabled(fonts.downloading)
                }
                if let failure = fonts.failure { Text(failure).font(.caption).foregroundStyle(.red) }
            } header: {
                Text("中文、日文和韩文")
            } footer: {
                Text("Noto Sans CJK 是安卓使用的中日韩字体。此汉化版已内置，可供使用系统字体的应用离线读取。游戏自带字体或字形图集缺失时，仍可能需要游戏自身支持。")
            }
        }
        .huskForm()
        .navigationTitle("字体")
    }
}

// MARK: - Performance

/// Whether this install was really signed with an entitlement: signing can drop them, and iOS gives no other sign that it did.
/// nil when the system does not answer.
private func huskHasEntitlement(_ name: String) -> Bool? {
    typealias Create = @convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    typealias Copy = @convention(c) (UnsafeMutableRawPointer, CFString, UnsafeMutableRawPointer?) -> Unmanaged<CFTypeRef>?
    let all = UnsafeMutableRawPointer(bitPattern: -2)      // RTLD_DEFAULT
    guard let c = dlsym(all, "SecTaskCreateFromSelf"), let v = dlsym(all, "SecTaskCopyValueForEntitlement"),
          let task = unsafeBitCast(c, to: Create.self)(nil) else { return nil }
    defer { Unmanaged<AnyObject>.fromOpaque(task).release() }
    guard let value = unsafeBitCast(v, to: Copy.self)(task, name as CFString, nil)?.takeRetainedValue() else { return false }
    return (value as? Bool) ?? false
}

struct PerformanceSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var gpuMode =
        UserDefaults.standard.object(forKey: "husk.gpuMode") as? Bool ?? true
    @State private var sound = UserDefaults.standard.bool(forKey: "husk.sound")
    @State private var soundDevice =
        UserDefaults.standard.object(forKey: "husk.soundDevice") as? Bool ?? true

    private func entitlementRow(_ title: String, _ name: String) -> some View {
        let on = huskHasEntitlement(name)
        return LabeledContent(title, value: on == nil ? "未知" : on! ? "已开启" : "已关闭")
    }

    var body: some View {
        HuskForm {
            Section {
                entitlementRow("提高内存限制", "com.apple.developer.kernel.increased-memory-limit")
                entitlementRow("扩展地址空间", "com.apple.developer.kernel.extended-virtual-addressing")
                LabeledContent("当前可用内存", value: ByteCountFormatter.string(fromByteCount: Int64(os_proc_available_memory()), countStyle: .memory))
            } header: {
                Text("内存")
            } footer: {
                Text("这里显示此次安装的签名权限。如果某项未开启，大型游戏可能提前退出；请使用保留这些权限的方式为 Husk 签名。")
            }
            Section {
                Picker("渲染器", selection: $gpuMode) {
                    Text("GPU").tag(true)
                    Text("CPU").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: gpuMode) { v in
                    UserDefaults.standard.set(v, forKey: "husk.gpuMode")
                    HuskLog.log("ui", v ? "GPU renderer selected" : "CPU renderer selected")
                }
            } header: {
                Text("渲染器")
            } footer: {
                Text(gpuMode
                     ? "安卓通过 Metal 使用真实 GPU 渲染，帧率通常明显更高，这是默认选项。"
                     : "由模拟 CPU 绘制每个像素，速度慢得多，仅建议在 GPU 渲染异常时使用。")
            }

            Section {
                DetailRow(label: "帧率",
                          value: runner.fps > 0
                                 ? String(format: "%.0f fps", runner.fps) : "—")
                DetailRow(label: "安卓屏幕",
                          value: "\(QemuRunner.lastGuestRes.w)×\(QemuRunner.lastGuestRes.h)")
            } header: {
                Text("现在")
            }

            Section {
                Toggle("声音", isOn: $sound)
                    .onChange(of: sound) { v in
                        UserDefaults.standard.set(v, forKey: "husk.sound")
                        HuskLog.log("ui", v ? "sound on" : "sound off")
                    }
                if sound {
                    Toggle("连接声音设备", isOn: $soundDevice)
                        .onChange(of: soundDevice) { v in
                            UserDefaults.standard.set(v, forKey: "husk.soundDevice")
                        }
                }
            } header: {
                Text("声音")
            } footer: {
                Text("添加声卡后无法保存安卓状态（QEMU 不支持为带此声卡的虚拟机创建快照），因此每次都要冷启动。开启或关闭此选项都需要冷启动一次。")
            }
        }
        .huskForm()
        .navigationTitle("Performance")
    }
}

// MARK: - Input

struct InputSettings: View {
    @State private var landscapeGuest =
        UserDefaults.standard.bool(forKey: "husk.landscapeGuest")
    @State private var customRes = UserDefaults.standard.bool(forKey: "husk.customRes")
    @State private var widthText = InputSettings.stored("husk.resWidth", 720)
    @State private var heightText = InputSettings.stored("husk.resHeight", 1280)

    /// Sizes worth offering without typing. Deliberately short: these are the
    /// shapes a phone guest is actually run at, not a catalogue of every panel
    /// ever made.
    private static let presets: [(name: String, w: Int, h: Int)] = [
        ("小屏——360 × 800", 360, 800),
        ("高清——720 × 1280", 720, 1280),
        ("全高清——1080 × 1920", 1080, 1920),
        ("横向高清——1280 × 720", 1280, 720),
        ("平板——1280 × 800", 1280, 800),
    ]

    private static func stored(_ key: String, _ fallback: Int) -> String {
        let v = UserDefaults.standard.integer(forKey: key)
        return String(v > 0 ? v : fallback)
    }

    /// What the typed numbers actually come to, or nothing if they are not a
    /// size the guest can be given.
    private var effective: (w: Int, h: Int)? {
        QemuRunner.validResolution(w: Int(widthText) ?? 0, h: Int(heightText) ?? 0)
    }

    var body: some View {
        HuskForm {
            Section {
                Picker("屏幕", selection: $landscapeGuest) {
                    Text("竖屏").tag(false)
                    Text("横屏").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(customRes)
                .onChange(of: landscapeGuest) { v in
                    UserDefaults.standard.set(v, forKey: "husk.landscapeGuest")
                    HuskLog.log("ui", v ? "guest panel will be landscape"
                                        : "guest panel will be portrait")
                }
            } header: {
                Text("屏幕")
            } footer: {
                Text(customRes
                     ? "自定义分辨率会直接决定屏幕形状，因此开启后此选项无效。需要横屏时请输入横向尺寸。"
                     : "安卓运行后无法改变屏幕形状，横屏游戏在竖屏内会缩成带黑边的狭窄区域。以横屏启动可让游戏铺满屏幕，竖屏应用则显示黑边。更改后需要冷启动一次。")
            }

            Section {
                Toggle("自定义分辨率", isOn: $customRes)
                    .onChange(of: customRes) { v in
                        UserDefaults.standard.set(v, forKey: "husk.customRes")
                        store()
                        HuskLog.log("ui", v ? "custom resolution on: "
                                            + "\(widthText)x\(heightText)"
                                            : "custom resolution off")
                    }

                if customRes {
                    Picker("预设", selection: Binding(
                        get: { presetIndex },
                        set: { i in
                            guard i >= 0, i < Self.presets.count else { return }
                            widthText = String(Self.presets[i].w)
                            heightText = String(Self.presets[i].h)
                            store()
                        })) {
                        ForEach(0..<Self.presets.count, id: \.self) { i in
                            Text(Self.presets[i].name).tag(i)
                        }
                        Text("自定义").tag(-1)
                    }

                    HStack {
                        Text("宽度")
                        Spacer()
                        TextField("720", text: $widthText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.technical())
                            .frame(width: 90)
                            .onChange(of: widthText) { _ in store() }
                    }
                    HStack {
                        Text("高度")
                        Spacer()
                        TextField("1280", text: $heightText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.technical())
                            .frame(width: 90)
                            .onChange(of: heightText) { _ in store() }
                    }

                    if let size = effective {
                        DetailRow(label: "安卓将使用",
                                  value: "\(size.w) × \(size.h)")
                    } else {
                        Text("宽和高都必须在 240 到 2560 之间。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                DetailRow(label: "当前运行尺寸", value: running)
            } header: {
                Text("分辨率")
            } footer: {
                Text("屏幕在虚拟机启动时创建，因此更改后需要冷启动，下次保存会覆盖旧尺寸的状态；改回也需要再次冷启动。尺寸会取整为 8 的倍数。分辨率越高越慢，而安卓显示密度不会随屏幕改变，因此更大的尺寸会显示更多内容，而非放大内容。")
            }

            Section {
                Text("触控始终可用。键盘与旋转控制位于安卓画面底部的胶囊栏中；手柄与指针尚未接入完整安卓模拟器。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("操控")
            }
        }
        .huskForm()
        .navigationTitle("Input")
    }

    /// The panel the guest actually has, which only means anything while there
    /// is a guest: the stored value is last launch's until one starts.
    private var running: String {
        guard QemuRunner.shared.isRunning else { return "尚未启动" }
        return "\(QemuRunner.lastGuestRes.w) × \(QemuRunner.lastGuestRes.h)"
    }

    /// Which preset the typed numbers are, if any.
    private var presetIndex: Int {
        guard let size = effective else { return -1 }
        return Self.presets.firstIndex { $0.w == size.w && $0.h == size.h } ?? -1
    }

    private func store() {
        UserDefaults.standard.set(Int(widthText) ?? 0, forKey: "husk.resWidth")
        UserDefaults.standard.set(Int(heightText) ?? 0, forKey: "husk.resHeight")
    }
}

// MARK: - Network

struct NetworkSettings: View {
    @State private var keepNetwork =
        UserDefaults.standard.object(forKey: "husk.keepNetwork") as? Bool ?? true

    var body: some View {
        HuskForm {
            Section {
                Toggle("存档时保留网络", isOn: $keepNetwork)
                    .onChange(of: keepNetwork) { v in
                        UserDefaults.standard.set(v, forKey: "husk.keepNetwork")
                    }
            } footer: {
                Text(keepNetwork
                     ? "保存时关闭应用，但保留安卓框架运行，以便恢复后网络仍可使用。"
                     : "保存时也停止安卓框架，清空全部 GPU 资源以提升稳定性，但网络可能需要冷启动后才能恢复。")
            }

            Section {
                Text("安卓通过 QEMU 自身网络中的虚拟以太网卡联网。手机局域网中的设备与安卓虚拟机无法直接互访。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("连接方式")
            }
        }
        .huskForm()
        .navigationTitle("Network")
    }
}

// MARK: - Play without JIT

struct JITLessSettings: View {
    @AppStorage(JITLess.key) private var jitless = false
    @ObservedObject private var certificate = SigningCertificate.shared
    @State private var pickedP12: Data?
    @State private var p12Password = ""
    @State private var cacheBytes = JITLess.cacheBytes

    var body: some View {
        HuskForm {
            Section {
                Toggle("无 JIT 游玩", isOn: $jitless)
                if cacheBytes > 0 {
                    DetailRow(label: "已转换的游戏", value: ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file), mono: false)
                    Button(role: .destructive) {
                        JITLess.clearCache(); cacheBytes = JITLess.cacheBytes
                    } label: { Label("移除已转换的游戏", systemImage: "trash") }
                }
            }
            .onAppear { cacheBytes = JITLess.cacheBytes }

            Section {
                if let info = certificate.info {
                    DetailRow(label: "团队", value: info.teamID)
                    DetailRow(label: "到期时间", value: info.expires.formatted(date: .abbreviated, time: .shortened), mono: false)
                    if info.expires < Date() {
                        Text("此证书已过期。请在侧载商店中刷新 Husk，然后重新导入证书。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } else {
                    DetailRow(label: "证书", value: "尚未导入", mono: false)
                }
                ForEach(SigningCertificate.Store.allCases) { store in
                    Button {
                        certificate.requestFromStore(store)
                    } label: { Label("从 \(store.title) 导入", systemImage: "arrow.down.circle") }
                }
                Button {
                    HuskFilePicker.present(types: [.pkcs12, .data], multiple: false, asCopy: true, onPick: { urls in
                        guard let url = urls.first else { return }
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        guard let data = try? Data(contentsOf: url) else { certificate.lastError = "无法读取该文件。"; return }
                        p12Password = ""
                        pickedP12 = data
                    }, onFail: { certificate.lastError = $0 })
                } label: { Label("导入 .p12 文件", systemImage: "doc.badge.plus") }
                if certificate.info != nil {
                    Button(role: .destructive) { certificate.remove() } label: { Label("移除证书", systemImage: "trash") }
                }
                if let why = certificate.lastError {
                    Text(why).font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("证书")
            }
        }
        .huskForm()
        .navigationTitle("无 JIT 游玩")
        .sheet(isPresented: Binding(get: { pickedP12 != nil }, set: { if !$0 { pickedP12 = nil } })) {
            NavigationView {
                Form {
                    Section {
                        SecureField("密码", text: $p12Password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("请输入私钥密码。如果没有设置密码，请留空。")
                    }
                }
                .navigationTitle("证书密码")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { pickedP12 = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("导入") {
                            if let data = pickedP12 { certificate.importP12(data, password: p12Password) }
                            pickedP12 = nil
                        }
                    }
                }
            }
        }
    }
}

// MARK: - JIT and sideloading

struct JITSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @State private var autoStart = Onboarding.autoStart
    @AppStorage(JITCoordinator.autoEnableKey) private var autoJIT = false
    @AppStorage(JITCoordinator.trollStoreAutoKey) private var trollStoreJIT = true
    @State private var keepAttached = JITBootstrap.keepDebuggerAttached

    private var pairingLabel: String {
        switch jit.pairingSource {
        case .onDevice: return "已在此设备上配对"
        case .imported: return "已导入文件"
        case nil: return "尚未配置"
        }
    }

    var body: some View {
        HuskForm {
            Section {
                JITCard()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                Picker("方式", selection: $jit.method) {
                    ForEach(JITMethod.allCases) { Text($0.title).tag($0) }
                }
                DetailRow(label: "StikDebug",
                          value: JITBootstrap.isStikDebugInstalled ? "installed" : "未找到", mono: false)
                DetailRow(label: "TrollStore",
                          value: JITBootstrap.isTrollStoreInstalled ? "installed" : "未找到", mono: false)
                DetailRow(label: "通过 TrollStore 安装",
                          value: JITBootstrap.isInstalledWithTrollStore ? "yes" : "no", mono: false)
                DetailRow(label: "越狱",
                          value: JITBootstrap.debuggedAtLaunch ? "已允许应用使用 JIT"
                               : JITBootstrap.isJailbroken ? "found" : "未找到", mono: false)
                DetailRow(label: "内置配对", value: pairingLabel, mono: false)
                Button {
                    jit.showSetup = true
                } label: {
                    Label("设置 JIT", systemImage: "wand.and.stars")
                }
            } header: {
                Text("开启 JIT 的其他方式")
            } footer: {
                Text(jit.method == .automatic
                     ? jit.automaticDescription + " 内置 StikJIT 需要 iOS 26、LocalDevVPN，以及一个"
                       + "配对文件；在 iOS 27 上，Husk 可自行创建配对文件。"
                     : HuskBuiltInJIT.unavailableReason ?? "内置 StikJIT 需要 LocalDevVPN 和配对文件；在 iOS 27 上，Husk 可自行创建配对文件。")
            }

            Section {
                DetailRow(label: "调试器",
                          value: JITBootstrap.isDebuggerAttached ? "attached" : "尚未附加",
                          mono: false)
                DetailRow(label: "可执行内存",
                          value: JITBootstrap.isLive ? "granted" : "尚未分配", mono: false)
                // The two routes, named separately. Either one is enough, and
                // when someone reports "JIT does not work" these two rows are
                // the whole diagnosis.
                DetailRow(label: "陷阱请求服务",
                          value: husk_ios_jit_self_route() != nil ? "无需使用"
                               : JITBootstrap.prewarmed ? "answering" : "无响应",
                          mono: false)
                if let route = husk_ios_jit_self_route() {
                    DetailRow(label: "由 Husk 创建",
                              value: String(cString: route) == "MAP_JIT" ? "MAP_JIT（动态代码签名）" : "普通内存（已调试或已越狱）",
                              mono: false)
                }
                // Cached answer only: running the probe from a view body
                // could freeze the app (see JITBootstrap.mapJITWorks).
                DetailRow(label: "MAP_JIT",
                          value: JITBootstrap.deviceEnforcesTXM ? "未使用（TXM）"
                               : JITBootstrap.mapJITResult.map { $0 ? "executes" : "refused" }
                                 ?? "尚未测试",
                          mono: false)
                DetailRow(label: "配置后的调试器",
                          value: JITBootstrap.detached ? "detached" : "attached",
                          mono: false)
                if let why = JITBootstrap.lastFailure {
                    Text(why).font(.caption).foregroundStyle(.orange)
                }
                if !JITBootstrap.ready {
                    Button {
                        jit.enable()
                    } label: {
                        Label("用 \(jit.resolvedMethod.title) 开启 JIT", systemImage: "bolt.fill")
                    }
                    .disabled(jit.busy)
                    Button {
                        _ = JITBootstrap.requestTrollStoreAttach()
                    } label: {
                        Label("用 TrollStore 开启 JIT", systemImage: "sparkles")
                    }
                }
            } header: {
                Text("JIT")
            } footer: {
                Text("Husk 需要可写入并执行的内存，在 iOS 上通常需要附加调试器。可通过响应陷阱请求的调试器，或内核为已调试进程允许的 MAP_JIT 映射来获得。任一方式可用即可；具体取决于设备与 iOS 版本，因此 Husk 会实际测试两种方式。")
            }

            if JITBootstrap.isInstalledWithTrollStore {
                Section {
                    Toggle("启动时用 TrollStore 开启 JIT", isOn: $trollStoreJIT)
                } footer: {
                    Text("每次 Husk 在没有 JIT 的情况下打开时，都会请 TrollStore 开启 JIT。需要打开 TrollStore 的 URL Scheme 设置。")
                }
            }

            Section {
                Toggle("启动时开启 JIT", isOn: $autoJIT)
                    .disabled(!HuskBuiltInJIT.isAvailable)
            } footer: {
                Text(HuskBuiltInJIT.isAvailable
                     ? "每次打开 Husk 时，如果 JIT 尚未开启，会请求内置 StikJIT 自动开启，让游戏无需额外点击即可就绪。需要先完成一次 StikJIT 配对设置。"
                     : "需要内置 StikJIT，适用于 iOS 26 及以上版本。")
            }

            Section {
                Toggle("启动时启动安卓", isOn: $autoStart)
                    .onChange(of: autoStart) { v in
                        UserDefaults.standard.set(v, forKey: "husk.autoStart")
                    }
            } footer: {
                Text("有 JIT 时，Husk 一打开就启动客机系统。")
            }

            Section {
                Toggle("保持调试器连接", isOn: $keepAttached)
                    .onChange(of: keepAttached) { v in JITBootstrap.keepDebuggerAttached = v }
            } footer: {
                Text("默认关闭。JIT 内存就绪后，Husk 会立即断开 StikDebug，以免 iOS 挂起调试器后导致整个应用停住。仅在需要收集 StikDebug 日志时开启。")
            }

            Section {
                Text("可通过游戏库的 + 按钮或“文件”页安装 APK。基础 APK 与配置分包必须一起选择；只安装基础包会因缺少原生库而失败。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("侧载")
            }
        }
        .huskForm()
        .navigationTitle("JIT & sideload")
    }
}

// MARK: - Saved machine

struct SavedMachineSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var autoSave =
        UserDefaults.standard.object(forKey: "husk.autoSave") as? Bool ?? true
    @State private var useSnapshot =
        UserDefaults.standard.object(forKey: "husk.downloadSnapshot") as? Bool ?? true
    @State private var askWhichToDelete = false
    @State private var deleteResult: String?
    @State private var askRemoveAndroid = false
    @State private var removeResult: String?
    @State private var androidBytes = GuestImage.shared.androidBytes
    @AppStorage(GuestImage.askUpdatesKey) private var askUpdates = true

    var body: some View {
        HuskForm {
            Section {
                Toggle("自动保存", isOn: $autoSave)
                    .onChange(of: autoSave) { v in
                        UserDefaults.standard.set(v, forKey: "husk.autoSave")
                        HuskLog.log("ui", v ? "automatic saving on" : "automatic saving off")
                    }
                Button {
                    QemuRunner.shared.saveState(reason: "asked from settings")
                } label: {
                    Label(runner.isSavingState ? "正在保存…" : "立即保存",
                          systemImage: "externaldrive.badge.checkmark")
                }
                .disabled(runner.isSavingState)
            } footer: {
                Text("Husk 可直接恢复已保存的虚拟机，通常只需几秒，而非等待数分钟开机。写入时画面会冻结。关闭后不会自动保存，包括安装应用后。")
            }

            Section {
                Button(role: .destructive) { askWhichToDelete = true } label: {
                    Label("删除保存的机器", systemImage: "trash")
                }
                .disabled(!QemuRunner.shared.hasSnapshot)
                if let deleteResult {
                    Text(deleteResult).font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text(QemuRunner.shared.hasSnapshot
                     ? "当前已保存："
                     + ((QemuRunner.shared.snapshotDisplay ?? "sw").contains("gl")
                        ? "GPU" : "software") + "."
                     : "没有保存的状态，安卓将冷启动。")
            }

            Section {
                Toggle("下载预启动快照", isOn: $useSnapshot)
                    .onChange(of: useSnapshot) { v in
                        UserDefaults.standard.set(v, forKey: "husk.downloadSnapshot")
                    }
            } footer: {
                Text("首次下载会增加约 2 GB。该快照由软件渲染器创建，不适用于 GPU 模式；GPU 模式会先冷启动一次，再保存自己的状态。")
            }

            Section {
                Button(role: .destructive) { askRemoveAndroid = true } label: {
                    Label("移除安卓", systemImage: "trash.slash")
                }
                .disabled(runner.isRunning || androidBytes == 0)
                if let removeResult {
                    Text(removeResult).font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text(androidBytes > 0
                     ? "安卓系统、数据与已保存的虚拟机占用 \(ByteCountFormatter.string(fromByteCount: androidBytes, countStyle: .file))。转译层的应用和游戏不需要这些内容。下次启动安卓时会重新下载。"
                     : "尚未下载安卓。")
            }

            Section {
                Toggle("询问安卓更新", isOn: $askUpdates)
            } footer: {
                Text("发布新的安卓映像或快照后，Husk 会询问一次是否下载。尚未下载安卓时不会询问。")
            }
        }
        .huskForm()
        .navigationTitle("Saved machine")
        .confirmationDialog("Which saved machine?", isPresented: $askWhichToDelete,
                            titleVisibility: .visible) {
            Button("GPU 机器", role: .destructive) { forget("gl", "GPU") }
            Button("软件机器", role: .destructive) { forget("sw", "software") }
            Button("取消", role: .cancel) { }
        } message: {
            Text("安卓会冷启动一次，然后保存新的快照。")
        }
        .confirmationDialog("Remove Android?", isPresented: $askRemoveAndroid, titleVisibility: .visible) {
            Button("移除安卓", role: .destructive) {
                let freed = GuestImage.shared.removeAll()
                androidBytes = GuestImage.shared.androidBytes
                removeResult = "已释放 \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))。"
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("安卓内安装或保存的所有内容都会被删除。转译层应用会保留它们的数据。")
        }
    }

    private func forget(_ mode: String, _ name: String) {
        if QemuRunner.shared.forgetSnapshot(mode: mode) {
            deleteResult = "已删除 \(name) 虚拟机状态，下次将冷启动。"
        } else {
            deleteResult = "没有保存的 \(name) 虚拟机状态，无需删除。"
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @State private var appIcon = HuskAppIcon.current
    @AppStorage(Theme.Appearance.key) private var appearance = Theme.Appearance.system
    @AppStorage(Holiday.key) private var holiday = true
    @ObservedObject private var theme = AppTheme.shared
    @Environment(\.colorScheme) private var scheme
    @State private var custom: Color = AppTheme.shared.accentColor

    private let iconColumns = [GridItem(.adaptive(minimum: 92), spacing: 14)]

    var body: some View {
        HuskForm {
            Section {
                Picker("外观", selection: $appearance) {
                    ForEach(Theme.Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { v in
                    HuskLog.log("ui", "appearance: \(v.rawValue)")
                }
                Toggle("节日装饰", isOn: $holiday)
            } header: {
                Text("主题")
            } footer: {
                Text("“跟随系统”会随手机切换浅色与深色。安卓画面本身不受影响。节日装饰会在十二月至一月初显示。")
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                    ForEach(AppTheme.presets) { preset in
                        Button {
                            theme.accentColor = preset.color
                            custom = preset.color
                        } label: {
                            swatch(preset.color, selected: preset.color.themeHex == theme.accentColor.themeHex)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                    }
                }
                .padding(.vertical, 6)

                ColorPicker("自定义颜色", selection: $custom, supportsOpacity: false)
                    .onChange(of: custom) { theme.accentColor = $0 }
            } header: {
                Text("强调色")
            } footer: {
                Text("为整个应用中的按钮、开关和选中状态着色。")
            }

            Section {
                LazyVGrid(columns: iconColumns, spacing: 14) {
                    ForEach(HuskAppIcon.allCases) { icon in
                        Button {
                            appIcon = icon
                            HuskAppIcon.apply(icon)
                        } label: {
                            VStack(spacing: 8) {
                                if let art = icon.preview(dark: scheme == .dark) {
                                    Image(uiImage: art)
                                        .resizable().scaledToFit()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(appIcon == icon ? Color.accentColor : .clear, lineWidth: 3))
                                }
                                Text(icon.title)
                                    .font(.caption)
                                    .foregroundStyle(appIcon == icon ? Color.accentColor : .primary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("应用图标")
            } footer: {
                Text("“自动”会跟随系统的浅色、深色与着色外观，其他选项固定一种样式。更改后 iOS 会显示确认提示，此提示无法关闭。")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func swatch(_ color: Color, selected: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 34, height: 34)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.9), lineWidth: selected ? 2 : 0).padding(-4))
            .overlay {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color.isLight ? .black : .white)
                }
            }
            .frame(maxWidth: .infinity)
    }
}

// MARK: - About

struct AboutSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var showLogs = false
    @AppStorage(TranslationLayer.devInfoKey) private var devInfo = false

    var body: some View {
        HuskPageList {
            Section {
                VStack(spacing: 8) {
                    HuskMark(size: 84)
                    Text("Husk").font(.title2.weight(.semibold))
                    Text("版本 \(Bundle.main.version)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("构建版本", value: Bundle.main.commit)
                LabeledContent("安卓映像", value: GuestImage.imageVersion)
                LabeledContent("渲染器",
                               value: runner.displayKind == .gl ? "GPU"
                                    : runner.displayKind == .software ? "CPU"
                                    : "尚未启动")
            }

            Section {
                Toggle(isOn: $devInfo) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("开发者信息")
                        Text("在安卓转译层界面中显示技术详情，包括库报告、设备检查与运行日志。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if devInfo {
                    NavigationLink { TLChecksView() } label: {
                        Label("设备检查", systemImage: "stethoscope")
                    }
                    NavigationLink { MassTestView() } label: {
                        Label("批量测试", systemImage: "square.stack.3d.down.forward")
                    }
                }
                Button { showLogs = true } label: {
                    Label("打开控制台", systemImage: "terminal")
                }
            } footer: {
                Text("Husk 可在 iPhone 上运行未经修改的安卓 APK。控制台显示 Husk 实时日志、安卓串口输出与 QEMU 输出，便于排查问题。")
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogs) { LogView() }
    }
}

extension Bundle {
    var version: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
    var commit: String {
        (infoDictionary?["HuskBuildCommit"] as? String) ?? "?"
    }
}
