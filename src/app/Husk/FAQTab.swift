// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Help: common problems and what to do about them, so a user stuck on JIT or on an app that will not open has an answer
/// without leaving Husk. A page in Settings (it was a tab of its own; four tabs read simpler than five).
struct FAQTab: View {
    @State private var query = ""

    private var sections: [FAQ.Section] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return FAQ.sections }
        return FAQ.sections.compactMap { s in
            let items = s.items.filter { $0.question.localizedCaseInsensitiveContains(q) || $0.answer.localizedCaseInsensitiveContains(q) }
            return items.isEmpty ? nil : FAQ.Section(title: s.title, symbol: s.symbol, items: items)
        }
    }

    var body: some View {
            HuskPageList {
                ForEach(sections) { s in
                    Section {
                        ForEach(s.items) { item in FAQRow(item: item, expanded: !query.isEmpty) }
                    } header: {
                        Label(s.title, systemImage: s.symbol)
                    }
                }
                if sections.isEmpty {
                    Text("没有匹配“\(query)”的内容。打开“设置”›“关于”›“打开控制台”查看 Husk 正在做什么。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("帮助")
            .searchable(text: $query, prompt: "搜索问题")
    }
}

private struct FAQRow: View {
    let item: FAQ.Item
    var expanded: Bool
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { open || expanded }, set: { open = $0 })) {
            Text(.init(item.answer))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        } label: {
            Text(item.question).font(.body.weight(.medium))
        }
    }
}

enum FAQ {
    struct Item: Identifiable { let question: String; let answer: String; var id: String { question } }
    struct Section: Identifiable { let title: String; let symbol: String; let items: [Item]; var id: String { title } }

    static let sections: [Section] = [
        Section(title: "JIT", symbol: "bolt.fill", items: [
            Item(question: "什么是 JIT？为什么 Husk 需要它？",
                 answer: "安卓应用和游戏会在运行时编译代码，需要可写入、随后又可执行的内存。iOS 只有在调试器附加到应用时才允许这样做。开启 JIT 会短暂附加调试器；未开启时，Husk 可以显示应用库，但无法启动安卓系统或游戏。"),
            Item(question: "应该选择哪种 JIT 开启方式？",
                 answer: "• **iOS 27 及以上：** 设置 › JIT › 在此 iPhone 上配对，无需电脑。\n• **iOS 26：** 内置 StikJIT，配合电脑生成的配对文件和 LocalDevVPN。\n• **更早的 iOS，或在 LiveContainer 中运行：** 使用 StikDebug 应用。\n• **通过 TrollStore 安装：** 在 TrollStore 中开启 URL Scheme 设置后使用 TrollStore。\n• **使用 Dopamine 越狱：** 在越狱设置中为应用开启 JIT。"),
            Item(question: "StikJIT 提示无法连接，或开启 JIT 失败",
                 answer: "1. 确认已安装并连接 **LocalDevVPN**，状态栏应显示 VPN 图标。\n2. 保持 Wi-Fi 开启，即使所有通信都留在 iPhone 本机。\n3. 开启 **开发者模式**（设置 › 隐私与安全性 › 开发者模式）。\n4. 首次运行时 Husk 会下载 Apple 开发者磁盘映像，请等待下载完成。\n5. 仍然失败时，断开并重新连接 LocalDevVPN，然后重新配对。"),
            Item(question: "开发者模式中没有出现“与 Husk 配对”",
                 answer: "先在 Husk 中点击 **开始配对**，并在提示时允许 **本地网络** 访问。如果之前拒绝过，请前往 设置 › 隐私与安全性 › 本地网络 › Husk 开启权限。Wi-Fi 和开发者模式都必须开启；首次开启开发者模式会重启 iPhone。"),
            Item(question: "配对文件失效了",
                 answer: "重置 iPhone 的信任设置后，配对文件会失效；iOS 更新后有时也会失效。请重新生成配对文件，或在 iOS 27 上直接用 iPhone 配对，然后在 设置 › JIT 中重新导入。"),
            Item(question: "StikDebug 打开了，但 JIT 仍未开启",
                 answer: "请单独打开 StikDebug，确认已导入配对文件、LocalDevVPN 已连接，并更新到最新版本。Husk 会自行把所需脚本发送给 StikDebug，无需在 StikDebug 中另行配置 Husk。"),
            Item(question: "为什么要反复开启 JIT？",
                 answer: "JIT 只在 Husk 进程运行期间有效。如果 iOS 在后台关闭 Husk，或你将其从应用切换器中划掉，下次启动就需要重新开启。有本机配对记录或配对文件时，只需点击一次。"),
            Item(question: "可以不使用 JIT 吗？",
                 answer: "可以浏览和导入应用。能否免 JIT 运行取决于应用及“免 JIT 运行”功能的兼容性；完整安卓系统仍需要 JIT。"),
        ]),
        Section(title: "Husk 本身", symbol: "app.badge", items: [
            Item(question: "Husk 完全无法打开",
                 answer: "• **打开后立刻退出：** 签名证书可能已过期，免费 Apple 账号签名通常有效 7 天。请使用原侧载工具重新签名或覆盖安装，以保留应用与存档。\n• **提示“不受信任的开发者”：** 前往 设置 › 通用 › VPN 与设备管理，信任你的证书。\n• **要求开发者模式：** 在 设置 › 隐私与安全性 中开启。"),
            Item(question: "游玩时 Husk 关闭了",
                 answer: "重新打开 Husk 后会显示发生的情况，并提供可分享的报告。通常是游戏内存不足，或使用了 Husk 尚未支持的功能。请先关闭其他应用；如果反复出现，请分享报告。"),
            Item(question: "如何获取日志来反馈问题？",
                 answer: "在应用库中打开应用详情页，点击 **分享报告**。Husk 自身的日志位于 设置 › 关于 › **打开控制台**；开启 **开发者信息** 后可以记录更多细节。"),
            Item(question: "如何更新 Husk？",
                 answer: "有新版本时 Husk 会提示。请使用同一侧载工具将新版 IPA 覆盖安装到旧版上，以保留应用库、应用和存档。"),
        ]),
        Section(title: "应用与游戏", symbol: "gamecontroller.fill", items: [
            Item(question: "如何添加 PS4 游戏？",
                 answer: "点击 +，选择解密的软件包（.pkg）、软件包文件夹，或已提取的游戏文件夹（包含 eboot.bin 和 sce_sys）。Husk 会将其安装到“文件”中的 PS4 游戏目录；更新包会放在对应游戏旁。零售软件包与 PS4 绑定，无法安装。PS4 游戏需要 iOS 17.4 或更高版本。"),
            Item(question: "应用无法打开",
                 answer: "在应用库中打开它的详情页，Husk 会说明停止原因：\n• **受保护的应用：** 检测真实安卓手机，或使用反作弊、DRM。Husk 不会绕过这些保护。\n• **处理器架构不兼容：** APK 只包含 x86 等非 ARM 代码，请获取 ARM（arm64-v8a 或 armeabi-v7a）版本。\n• **应用不完整或缺少数据：** 需要分包或 OBB，请导入完整的 .apks、.xapk 或 .apkm。\n• **需要 Google：** 应用依赖 Husk 无法提供的 Google 账号或 Play 服务。\n• **使用了尚未实现的功能：** 请分享报告，帮助开发者添加支持。"),
            Item(question: "画面一直黑屏",
                 answer: "大型游戏首次启动时需要准备代码和数据，可能耗时约一分钟。如果之后仍然黑屏，请关闭并重新打开一次；仍无变化时请分享报告。"),
            Item(question: "修改版或重新打包的 APK 崩溃",
                 answer: "部分网站提供的重打包版本会改动应用代码、加入额外运行库或完整性检查，兼容性更容易出问题。请优先尝试开发者提供的原始 APK。"),
            Item(question: "可以导入哪些文件？",
                 answer: "支持 .apk，以及 .apks、.xapk、.apkm 格式的分包。可以分享文件到 Husk，从“文件”打开，或点击应用库中的 +。"),
            Item(question: "游戏运行缓慢，或者手机发热",
                 answer: "请关闭其他应用，并让手机适当散热。游戏虽然原生运行，但部分由安卓硬件承担的工作需要 Husk 用 CPU 完成。低电量模式也会降低运行速度。"),
            Item(question: "可以使用手柄吗？",
                 answer: "可以。在 iPhone 的蓝牙设置中连接手柄，支持手柄的游戏即可识别。"),
            Item(question: "游戏运行时可以继续使用 Husk 吗？",
                 answer: "在设置中开启 **以窗口打开应用**，之后应用会在可移动、缩放和最小化的窗口中打开。"),
            Item(question: "无法使用 Google 登录",
                 answer: "Husk 没有 Google Play 服务，因此“使用 Google 登录”可能失败。如果应用支持，请改用邮箱或其他登录方式。"),
        ]),
        Section(title: "存档与存储", symbol: "externaldrive.fill", items: [
            Item(question: "存档在哪里？",
                 answer: "每个应用的数据都保存在 Husk 内。在应用详情页中，**备份存档** 用于导出数据，**恢复存档** 用于导入，也可以迁移到另一台 iPhone。"),
            Item(question: "Husk 占用了很多存储空间",
                 answer: "导入的应用及其数据保存在 Husk 文件夹中。可在详情页移除不再使用的游戏。完整安卓系统还需要约 2 GB 下载，仅运行完整安卓系统时才需要。"),
        ]),
        Section(title: "安卓", symbol: "cpu", items: [
            Item(question: "应用运行与完整安卓系统有什么区别？",
                 answer: "大多数应用和游戏可以像原生应用一样直接在 iPhone 上运行。完整安卓系统是独立且较慢的选项，适合只能在完整安卓环境中运行的程序。"),
            Item(question: "安卓启动耗时很久",
                 answer: "首次启动需要下载系统镜像并冷启动，耗时数分钟。之后 Husk 会恢复保存的系统状态，速度会明显加快。"),
        ]),
    ]
}
