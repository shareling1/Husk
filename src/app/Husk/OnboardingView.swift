// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UniformTypeIdentifiers

/// What Husk asks on a first install, and remembers.
///
/// Deliberately versioned rather than a plain "seen it" flag: a later build that
/// adds a question needs to be able to ask it, and existing installs must not be
/// dragged back through the whole flow for one new answer. Bumping
/// `Onboarding.version` is what re-opens it.
enum Onboarding {
    /// Raise this when a question is added that existing installs must answer.
    static let version = 2   // 3.0: everyone goes through the new setup once

    private static let key = "husk.onboardingVersion"

    static var needed: Bool {
        UserDefaults.standard.integer(forKey: key) < version
    }

    static func complete() {
        UserDefaults.standard.set(version, forKey: key)
    }

    /// What apps inside Husk are told about where you are, chosen in setup.
    // TODO: hand these to the guest (TL locale/time zone and Android's persist.sys.locale / TZ); stored only for now.
    static let languageKey = "husk.guest.language"
    static let regionKey = "husk.guest.region"
    static let timeZoneKey = "husk.guest.timeZone"

    /// Start the guest as soon as the app opens, when JIT is available.
    static var autoStart: Bool {
        UserDefaults.standard.bool(forKey: "husk.autoStart")
    }
}

/// First run: setup in the manner of the iPhone's own -- language, region, time zone, the
/// optional settings, JIT -- and an offer of a walkthrough. Shown once; people who set up an older Husk get What's New instead.
struct OnboardingView: View {
    let onDone: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, language, region, timeZone, options, jit, ask, tour
    }

    @State private var step: Step = .welcome
    @State private var forward = true
    @State private var tourPage = 0

    @State private var language = UserDefaults.standard.string(forKey: Onboarding.languageKey) ?? "zh-Hans"
    @State private var region = Locale.current.huskRegionCode ?? "US"
    @State private var timeZone = TimeZone.current.identifier
    @State private var query = ""

    @State private var autoStart = false
    @State private var landscape = UserDefaults.standard.bool(forKey: "husk.landscapeGuest")
    @State private var sound = UserDefaults.standard.bool(forKey: "husk.sound")
    @State private var autoSave = UserDefaults.standard.object(forKey: "husk.autoSave") as? Bool ?? true
    @AppStorage(Theme.Appearance.key) private var appearance = Theme.Appearance.system
    @ObservedObject private var theme = AppTheme.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @ObservedObject private var certificate = SigningCertificate.shared
    @AppStorage(JITLess.key) private var jitless = false
    @State private var settingUpJIT = false
    @State private var pickedP12: Data?
    @State private var p12Password = ""

    var body: some View {
        ZStack {
            Theme.backdrop
            setup
        }
        .sheet(isPresented: $settingUpJIT) { JITSetupFlow() }
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

    // MARK: frame

    private var setup: some View {
        VStack(spacing: 0) {
            HStack {
                if step != .welcome {
                    Button { go(back: true) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                            Text("返回")
                        }
                    }
                    .accessibilityLabel("返回")
                }
                Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal, 16)

            ZStack {
                page(step)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if step != .ask {
                VStack(spacing: 14) {
                    dots
                    Button(step == .tour && tourPage == Self.tour.count - 1 ? "开始使用 Husk" : "继续") { next() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: 560)
    }

    private var dots: some View {
        let count = step == .tour ? Self.tour.count : Step.ask.rawValue + 1
        let current = step == .tour ? tourPage : step.rawValue
        return HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Theme.text : Color.secondary.opacity(0.3))
                    .frame(width: i == current ? 18 : 6, height: 6)
            }
        }
        .animation(.snappy, value: current)
    }

    private func next() {
        if step == .tour {
            if tourPage < Self.tour.count - 1 { withAnimation(.snappy) { tourPage += 1 } } else { finish() }
            return
        }
        query = ""
        forward = true
        withAnimation(.snappy) { step = Step(rawValue: step.rawValue + 1) ?? .ask }
    }

    private func go(back: Bool) {
        query = ""
        forward = false
        withAnimation(.snappy) {
            if step == .tour, tourPage > 0 { tourPage -= 1; return }
            step = Step(rawValue: step.rawValue - 1) ?? .welcome
        }
    }

    private func finish() {
        let d = UserDefaults.standard
        d.set(autoStart, forKey: "husk.autoStart")
        d.set(landscape, forKey: "husk.landscapeGuest")
        d.set(sound, forKey: "husk.sound")
        d.set(autoSave, forKey: "husk.autoSave")
        d.set(language, forKey: Onboarding.languageKey)
        // Husk's own screens and the apps in it use this language from the next launch (#156): iOS's per-app language, which the
        // runtime also reads for the apps' locale. Only when it differs from the phone's, so the phone's choice keeps applying otherwise.
        d.set(["zh-Hans"], forKey: "AppleLanguages")
        d.set(region, forKey: Onboarding.regionKey)
        d.set(timeZone, forKey: Onboarding.timeZoneKey)
        Onboarding.complete()
        WhatsNew.markSeen()
        HuskLog.log("ui", "setup complete: language=\(language) region=\(region) timeZone=\(timeZone) autoStart=\(autoStart) "
                        + "landscape=\(landscape) sound=\(sound) autoSave=\(autoSave)")
        onDone()
    }

    // MARK: pages

    @ViewBuilder
    private func page(_ step: Step) -> some View {
        switch step {
        case .welcome: welcome
        case .language:
            picker(symbol: "globe", title: "语言",
                   subtitle: "保存安卓应用和游戏的语言偏好。原版部分运行环境尚未接入此选项；Husk 界面固定为简体中文。",
                   rows: Self.languages, selection: $language)
        case .region:
            picker(symbol: "map.fill", title: "地区",
                   subtitle: "用于需要获取你所在国家或地区的应用。",
                   rows: Self.regions, selection: $region)
        case .timeZone:
            picker(symbol: "clock.fill", title: "时区",
                   subtitle: "用于显示本地时间的应用。",
                   rows: Self.timeZones, selection: $timeZone)
        case .options: options
        case .jit: jitPage
        case .ask: ask
        case .tour: tourCard(Self.tour[tourPage]).id(tourPage)
        }
    }

    private func header(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 50, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(height: 60)
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            HuskMark(size: 110)
            Text("欢迎使用 Husk")
                .font(.system(size: 34, weight: .bold))
            Text("安卓和 PS4 游戏，就在你的 iPhone 上。")
                .font(.title3).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("先做几个简单的选择。这里的所有设置以后都可以在“设置”中更改。")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
        }
    }

    /// A list to choose one from, searchable, with the choice ticked.
    private func picker(symbol: String, title: String, subtitle: String, rows: [SetupChoice],
                        selection: Binding<String>) -> some View {
        let shown = rows.filter { matches(query, $0.name, $0.id) }
        return VStack(spacing: 16) {
            header(symbol, title, subtitle)
            SearchField(text: $query, prompt: "搜索")
                .padding(.horizontal, 20)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shown) { row in
                            Button { selection.wrappedValue = row.id } label: {
                                HStack {
                                    Text(row.name).foregroundStyle(Theme.text)
                                    Spacer()
                                    if selection.wrappedValue == row.id {
                                        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 46)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(row.id)
                            if row.id != shown.last?.id { RowDivider().padding(.leading, -46) }
                        }
                    }
                    .huskCard()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
                .huskDismissKeyboardOnScroll()
                .onAppear { proxy.scrollTo(selection.wrappedValue, anchor: .center) }
            }
        }
    }

    private var options: some View {
        ScrollView {
            VStack(spacing: 16) {
                header("slider.horizontal.3", "个性化设置", "所有选项均为可选，可随时在设置中更改。")

                VStack(alignment: .leading, spacing: 12) {
                    Text("外观").font(.headline)
                    Picker("外观", selection: $appearance) {
                        ForEach(Theme.Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appearance) { Theme.apply($0) }
                    Text("强调色").font(.headline).padding(.top, 4)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(AppTheme.presets) { preset in
                            let selected = preset.color.themeHex == theme.accentColor.themeHex
                            Button { theme.accentColor = preset.color } label: {
                                Circle().fill(preset.color)
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(Theme.text, lineWidth: selected ? 2.5 : 0).padding(-4))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(preset.name)
                        }
                    }
                }
                .padding(16)
                .huskCard()

                choice(icon: "bolt.fill", title: "打开 Husk 时启动安卓",
                       detail: "默认关闭。完整安卓模拟器仍处于实验阶段，随应用启动可能带来异常、冻结或崩溃，并拖慢启动速度。游戏和应用并不一定需要它。",
                       isOn: $autoStart, caution: true)
                choice(icon: "rectangle.landscape.rotate", title: "横向安卓屏幕",
                       detail: "适用于安卓模拟器：游戏填满横屏界面，竖屏应用则显示黑边。",
                       isOn: $landscape)
                choice(icon: "speaker.wave.2.fill", title: "安卓声音",
                       detail: "为模拟器添加声卡。开启后无法保存运行状态，每次启动都需要冷启动。",
                       isOn: $sound)
                choice(icon: "externaldrive.badge.checkmark", title: "自动保存安卓状态",
                       detail: "安卓运行稳定后自动保存，使后续启动只需几秒钟。",
                       isOn: $autoSave)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func choice(icon: String, title: String, detail: String, isOn: Binding<Bool>, caution: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: caution ? "exclamationmark.triangle.fill" : icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(caution ? Color.orange : Theme.accent)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(caution ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.accent)
        }
        .padding(16)
        .huskCard()
    }

    /// What the JIT page says is already in place, if anything.
    private var jitState: String? {
        if JITBootstrap.ready { return "JIT 已开启。" }
        if jit.method == .stikDebug { return "Husk 将使用 StikDebug。" }
        if jit.method == .trollStore { return "Husk 将使用 TrollStore。" }
        switch jit.pairingSource {
        case .onDevice: return "已在此设备上完成配对。"
        case .imported: return "配对文件已导入。"
        case nil: return nil
        }
    }

    private var jitPage: some View {
        ScrollView {
            VStack(spacing: 18) {
                header("bolt.fill", "游戏如何运行",
                       "多数游戏需要 JIT，或使用侧载证书进行无 JIT 游玩。")
                if let state = jitState {
                    Label(state, systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium)).foregroundStyle(.green)
                }
                Button(jitState == nil ? "立即设置 StikJIT" : "更改 JIT 设置") { settingUpJIT = true }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        jitless = true
                    } label: {
                        HStack {
                            Text("无 JIT 游玩")
                                .font(.body.weight(.semibold))
                            Spacer()
                            if jitless { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                    .foregroundStyle(Theme.accent)
                    Text("导入 SideStore 或 AltStore 安装 Husk 时使用的证书，或导入 .p12 文件。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let info = certificate.info {
                        Text("证书：团队 \(info.teamID)。")
                            .font(.caption).foregroundStyle(.green)
                    }
                    ForEach(SigningCertificate.Store.allCases) { store in
                        Button("从 \(store.title) 导入") {
                            jitless = true
                            certificate.requestFromStore(store)
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    }
                    Button("导入 .p12 文件") {
                        jitless = true
                        HuskFilePicker.present(types: [.pkcs12, .data], multiple: false, asCopy: true, onPick: { urls in
                            guard let url = urls.first else { return }
                            let scoped = url.startAccessingSecurityScopedResource()
                            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                            guard let data = try? Data(contentsOf: url) else { certificate.lastError = "无法读取该文件。"; return }
                            p12Password = ""
                            pickedP12 = data
                        }, onFail: { certificate.lastError = $0 })
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    if let why = certificate.lastError {
                        Text(why).font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 28)

                Text("可以跳过：游戏需要时 Husk 会再次询问。JIT 位于“设置 › JIT 与侧载”中，“无 JIT 游玩”就在其旁边。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
            .padding(.bottom, 16)
        }
    }

    private var ask: some View {
        VStack(spacing: 18) {
            Spacer()
            header("map.circle.fill", "需要快速入门介绍吗？", "快速了解 Husk：游戏在哪里、如何添加，以及设置入口。")
            Spacer()
            VStack(spacing: 12) {
                Button("带我看看") {
                    forward = true
                    tourPage = 0
                    withAnimation(.snappy) { step = .tour }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("以后再说") { finish() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    private struct TourCard { let symbol: String; let title: String; let text: String }

    private static let tour: [TourCard] = [
        TourCard(symbol: "house.fill", title: "主页",
                 text: "游戏按最近游玩的顺序陈列。点击游戏可选中并显示背景，再次点击或按“游玩”即可启动。⋯ 按钮提供设置等更多选项。"),
        TourCard(symbol: "square.grid.2x2.fill", title: "游戏库",
                 text: "按平台展示已添加的内容。可用“全部”“安卓”和“PS4”筛选，按名称搜索，长按游戏查看选项。圆点表示运行情况：绿色可玩、橙色可打开、红色无法运行。"),
        TourCard(symbol: "plus.circle.fill", title: "添加游戏",
                 text: "点击 + 添加安卓 APK、应用包（.xapk、.apkm、.apks）或 PS4 游戏：fake package（.pkg）、包含安装包的文件夹或已解压的游戏文件夹。也可以从“文件”或 Safari 分享到 Husk。"),
        TourCard(symbol: "cart.fill", title: "商店",
                 text: "使用访客或自己的账号浏览并下载 Google Play 中的安卓应用，还可查看各应用在 Husk 中的运行情况。"),
        TourCard(symbol: "bolt.fill", title: "设置与 JIT",
                 text: "游戏需要 JIT，或使用证书进行无 JIT 游玩，两者均可在设置中配置。设置还包含性能、外观、输入及可选的完整安卓模拟器。"),
        TourCard(symbol: "questionmark.circle.fill", title: "帮助",
                 text: "遇到问题？“设置 › 帮助”提供常见问题解答。导致 Husk 崩溃的游戏还会留下可分享的报告。"),
    ]

    private func tourCard(_ card: TourCard) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: card.symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 96, height: 96)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            Text(card.title).font(.system(size: 32, weight: .bold))
            Text(card.text)
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
            Spacer()
        }
        .transition(.opacity)
    }

    // MARK: lists

    private static var defaultLanguage: String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") { return "zh-Hant" }
        if preferred.hasPrefix("zh") { return "zh-Hans" }
        if preferred.hasPrefix("pt-BR") { return "pt-BR" }
        if preferred.hasPrefix("ja") { return "ja" }
        let code = Locale.current.huskLanguageCode ?? "en"
        return languages.contains { $0.id == code } ? code : "en"
    }

    private static let languages: [SetupChoice] = {
        let codes = ["en", "es", "fr", "de", "it", "pt", "pt-BR", "ru", "uk", "pl", "nl", "sv", "da", "nb", "fi", "tr", "el",
                     "cs", "hu", "ro", "ar", "he", "hi", "th", "vi", "id", "ms", "ja", "ko", "zh-Hans", "zh-Hant"]
        return codes.map { code in
            let native = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
            let here = Locale.current.localizedString(forIdentifier: code) ?? code
            return SetupChoice(id: code, name: native == here ? native.capitalized : "\(native.capitalized) – \(here)")
        }
    }()

    private static let regions: [SetupChoice] = {
        Locale.isoRegionCodes
            .compactMap { code in Locale.current.localizedString(forRegionCode: code).map { SetupChoice(id: code, name: $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    private static let timeZones: [SetupChoice] = {
        TimeZone.knownTimeZoneIdentifiers.map { id in
            let city = id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id
            let tz = TimeZone(identifier: id)
            let offset = tz.map { z -> String in
                let s = z.secondsFromGMT()
                return String(format: "GMT%@%d:%02d", s >= 0 ? "+" : "-", abs(s) / 3600, abs(s) % 3600 / 60)
            } ?? ""
            return SetupChoice(id: id, name: "\(city) (\(offset)) · \(id)")
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()
}

/// One row of a setup list: what is stored, and what is shown.
struct SetupChoice: Identifiable { let id: String; let name: String }
