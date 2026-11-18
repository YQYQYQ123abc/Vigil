import AppKit
import Combine
import SwiftUI

private final class FolderRemovalSelection: ObservableObject {
    @Published var folder: ProtectedFolder?
}

/// 设备 → 本机 → 保护目录
struct ProtectedFoldersView: View {
    @ObservedObject var store: ProtectedFolderStore
    @StateObject private var removal = FolderRemovalSelection()

    var body: some View {
        Group {
            if store.folders.isEmpty {
                ContentUnavailableView {
                    Label("还没有保护目录", systemImage: "folder.badge.plus")
                } description: {
                    Text("选择电脑上已有的目录。目录会留在原位置，继续用 Finder 和原来的应用使用。")
                } actions: {
                    Button("添加目录…") { add() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    Section {
                        LocalProtectionStatusRow(store: store)
                    }
                    Section("保护目录") {
                        ForEach(store.folders) { folder in
                            FolderRow(folder: folder, status: store.statuses[folder.id] ?? .available)
                                .contextMenu {
                                    if store.statuses[folder.id]?.isUsable ?? false {
                                        Button("在 Finder 中显示") { reveal(folder) }
                                    }
                                    Button("移出清单…", role: .destructive) { removal.folder = folder }
                                }
                                .swipeActions {
                                    Button("移出清单", role: .destructive) { removal.folder = folder }
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle("保护目录")
        .toolbar {
            ToolbarItem {
                Button("添加目录…", systemImage: "plus") { add() }
            }
        }
        .confirmationDialog(
            "移出「\(removal.folder?.name ?? "")」？",
            isPresented: Binding(get: { removal.folder != nil }, set: { if !$0 { removal.folder = nil } }),
            titleVisibility: .visible,
            presenting: removal.folder
        ) { folder in
            Button("移出清单", role: .destructive) {
                Task { await store.remove(folder) }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("移出后，目录及其中的文件不会被改动或删除，位置和内容保持原样。")
        }
    }

    private func add() {
        store.add(urls: FolderPicker.pick())
    }

    private func reveal(_ folder: ProtectedFolder) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)])
    }
}

private struct FolderRow: View {
    let folder: ProtectedFolder
    let status: FolderStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.isUsable ? "folder" : "folder.badge.questionmark")
                .font(.title2)
                .foregroundStyle(status.isUsable ? Color.accentColor : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let note = status.note {
                    Text(note).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(status.label)
                .font(.subheadline)
                .foregroundStyle(status.isUsable ? Color.secondary : Color.orange)
        }
        .padding(.vertical, 4)
        .help(folder.path)
    }
}

/// 本机保护状态行：由真实配置推出，与示例事件无关。
struct LocalProtectionStatusRow: View {
    @ObservedObject var store: ProtectedFolderStore

    var body: some View {
        let summary = store.summary
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.statusText)
                Text(summary.explanation).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: summary.symbol)
        }
    }
}

/// 设备详情里进入保护目录页的入口。
struct ProtectedFoldersLink: View {
    @ObservedObject var store: ProtectedFolderStore

    var body: some View {
        NavigationLink {
            ProtectedFoldersView(store: store)
        } label: {
            LabeledContent("保护目录", value: store.summary.countText)
        }
    }
}

/// 清单的提示（重复、合并、读取失败等）。挂在应用根部，在任何页面都能看到。
struct StorePromptAlert: ViewModifier {
    @ObservedObject var store: ProtectedFolderStore

    func body(content: Content) -> some View {
        content.alert(
            store.currentPrompt?.title ?? "",
            isPresented: Binding(get: { store.currentPrompt != nil }, set: { _ in }),
            presenting: store.currentPrompt
        ) { prompt in
            switch prompt {
            case .notice:
                Button("好", role: .cancel) { store.resolveCurrentPrompt(confirmMerge: false) }
            case .merge:
                Button("合并") { store.resolveCurrentPrompt(confirmMerge: true) }
                Button("取消", role: .cancel) { store.resolveCurrentPrompt(confirmMerge: false) }
            }
        } message: { prompt in
            Text(prompt.message)
        }
    }
}
