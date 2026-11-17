// SPDX-License-Identifier: GPL-2.0-or-later
// Import APK: a file from Files (or dropped on iPad), what Husk takes, and the other ways to get a game: the Store, a link.
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @ObservedObject private var router = Router.shared
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var askingLink = false
    @State private var dropping = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    dropZone
                    VStack(alignment: .leading, spacing: 10) {
                        Text("支持的格式").font(.system(size: 15, weight: .semibold)).foregroundStyle(Console.text)
                        format("APK")
                        format("分包 APK（.xapk、.apkm、.apks）")
                        format("OBB / 资源包")
                        format("PS4 游戏文件夹（已解压）")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Console.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("或者从这里获取").font(.system(size: 15, weight: .semibold)).foregroundStyle(Console.text)
                        source("Play Store", "bag.fill") { dismiss(); router.tab = .store }
                        source("外部链接", "link") { askingLink = true }
                    }
                }
                .padding(20)
            }
            .background(Console.page.ignoresSafeArea())
            .navigationTitle("导入 APK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .alert("从链接下载", isPresented: $askingLink) {
                TextField("https://…", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("下载") {
                    let l = link; link = ""
                    Task { await Downloads.shared.add(link: l) }
                    dismiss(); router.showDownloads = true
                }
                Button("取消", role: .cancel) { link = "" }
            } message: {
                Text("APK、应用包或 zip 的直接链接。它会出现在“下载”中，之后 Husk 会询问放到哪里。")
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Console.textDim)
            Text(UIDevice.current.userInterfaceIdiom == .pad ? "把 APK 文件拖到这里" : "从“文件”中选择 APK")
                .font(.system(size: 15)).foregroundStyle(Console.textDim)
            if UIDevice.current.userInterfaceIdiom == .pad { Text("or").font(.system(size: 13)).foregroundStyle(Console.textDim) }
            Button { dismiss(); router.addSomething() } label: {
                Text("选择文件").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 28).frame(height: 44)
                    .background(Console.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(CardButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(dropping ? Theme.accent.opacity(0.12) : Console.card.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(dropping ? Theme.accent : Console.outline, style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])))
        .onDrop(of: [.fileURL, .item], isTargeted: $dropping) { providers in
            for p in providers {
                p.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, _ in
                    guard let url else { return }
                    // the provider's copy goes when this returns: keep one of our own
                    let keep = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: keep)
                    guard (try? FileManager.default.copyItem(at: url, to: keep)) != nil else { return }
                    DispatchQueue.main.async { IncomingFiles.shared.receive([keep]); dismiss() }
                }
            }
            return true
        }
    }

    private func format(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent)
            Text(text).font(.system(size: 14)).foregroundStyle(Console.text.opacity(0.9))
        }
    }

    private func source(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 24)
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Console.text)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Console.textDim)
            }
            .padding(.horizontal, 14).frame(height: 52)
            .background(Console.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
    }
}
