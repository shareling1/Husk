# Husk 简体中文专用构建

基于 Leviidev/Husk 3.4 的应用源码（29abb512d81bf8cc08babcbe7f7007cb557208ef）。
界面固定为简体中文，保留原版安卓客体语言偏好选择（部分运行环境尚未接入此选项）。保留品牌、协议字段、文件路径与底层日志，不将它们误译为中文。
translation-manifest.json 记录逐项补译，覆盖 SwiftUI 静态文案以及原先绕过本地化的动态 String 文案。
未附带任何游戏，不改变 JIT、签名和系统兼容性要求。

## 字体
安装包内置 Noto Sans CJK Regular TTC（SIL OFL 1.1，许可证随包提供），无需联网下载。
UIAppFonts 注册字体；CJKFonts 指向包内字体目录，供安卓转译层的 /system/fonts 回退查找使用。
游戏专有字形图集或游戏自身缺字仍需游戏本身支持，不能仅靠系统字体保证修复。

## GitHub Actions
.github/workflows/build-zh-tipa.yml 在 macOS 26 runner 上从源码重新编译应用与 Rust 配对库，
通过官方 package_ipa.sh --trollstore 创建真正的 .tipa。
未修改的 QEMU、ANGLE、MoltenVK、PS4 运行库、Java/Android 系统资源取自 SHA-256 校验过的官方 3.4 TIPA，保留其许可。
不是重新命名或只重打包官方可执行文件。源代码与依赖来源公开记录，字体固定提交与校验值。

自动检查：本地化语法、协议字段与字体路径配置检查、Xcode 编译、Mach-O/资源完整性、字体哈希与中日韩字形样本、签名与 TrollStore 禁用权限。
原版字体路径 C 单元测试仅在 ARM 主机执行；Intel runner 因 ARM 寄存器依赖跳过此项，未修改生产运行时以迁就主机测试。
未连接 iPhone 进行安装、布局或游戏运行测试；外部网页、游戏自身界面和底层诊断可能仍为原语言。

构建兼容修复：将个人资料工具栏的可选项条件移至 ToolbarItem 内部，避免 iOS 15.5 目标调用仅 iOS 16 可用的 ToolbarContentBuilder.buildIf；未提高最低系统版本。

## Build 150：Unity 中日韩空白字形兼容修复
- 将字体文件映射与目录枚举共用同一字体 VFS。`opendir/readdir`、`scandir`、NDK 字体枚举均能发现额外的内置/下载 TTC，而不把包内其他文件暴露为系统字体。
- 映射 `$ANDROID_ROOT/etc/fonts.xml` 与 `font_fallback.xml`，与 `/system/etc` 一致；Java 使用的其他数据路径保持不变。
- 系统字体 XML 的 CJK 项改为与固定的静态 Noto TTC 一致：正确地区索引、真实 PostScript 名、移除不存在的变字体轴；缺失的 CJK serif 回退使用同一可用 TTC。
- 启动日志新增 `fonts: Android discovery entries=... CJK-listed=yes CJK-readable=yes`，便于确认已运行修复版。
- 新增可在 Intel/ARM macOS 运行的生产字体 VFS 测试，启用 AddressSanitizer/UBSan。原有整体 IO 单测仍只在 ARM 主机执行。
- 已静态确认一个 Unity 2022.3 ARM64 包中的 Arial/Calibri 缺少 CJK 字形、依赖系统补字；未将 APK 或任何游戏资源上传到仓库。
- 这些是确认的兼容性缺口；编译/单测通过不等于该游戏已在 iPhone 上实测通过。如仍有空白，需从修复版收集对应启动/字体日志继续排查。
