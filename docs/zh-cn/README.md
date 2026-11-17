# Husk 简体中文专用构建

基于 Leviidev/Husk 3.4 的应用源码（29abb512d81bf8cc08babcbe7f7007cb557208ef）。
界面固定为简体中文，安卓客体语言仍可独立选择。保留品牌、协议字段、文件路径与底层日志，不将它们误译为中文。
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

自动检查：本地化语法、字体路径 C 测试、Xcode 编译、Mach-O/资源完整性、字体哈希与中日韩字形样本、签名与 TrollStore 禁用权限。
未连接 iPhone 进行安装、布局或游戏运行测试；外部网页、游戏自身界面和底层诊断可能仍为原语言。
