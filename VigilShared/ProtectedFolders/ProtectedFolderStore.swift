import Combine
import Foundation

/// 需要用户看到的提示。多条提示排队，一次显示一条。
enum StorePrompt: Equatable {
    case notice(title: String, message: String)
    /// 新选的目录包含清单中已有的目录，询问是否合并。
    case merge(newFolder: ProtectedFolder, childNames: [String])

    var title: String {
        switch self {
        case .notice(let title, _): return title
        case .merge(let folder, _): return "合并为「\(folder.name)」？"
        }
    }

    var message: String {
        switch self {
        case .notice(_, let message): return message
        case .merge(let folder, let names):
            let list = names.map { "「\($0)」" }.joined(separator: "、")
            return "「\(folder.name)」包含了清单中已有的 \(names.count) 个目录：\(list)。合并后由「\(folder.name)」统一覆盖，这些目录会从清单中移出。目录和文件本身不会被改动。"
        }
    }
}

/// 保护目录清单：添加、去重、移出、状态刷新与持久化。
/// 只读写清单本身，不会修改用户磁盘上的任何目录或文件。
final class ProtectedFolderStore: ObservableObject {
    @Published private(set) var folders: [ProtectedFolder] = []
    @Published private(set) var statuses: [UUID: FolderStatus] = [:]
    @Published private(set) var currentPrompt: StorePrompt?

    private let access: FolderAccess?
    private let persistence: FolderPersistence?
    private let authorizer: ProtectionChangeAuthorizing
    private var promptQueue: [StorePrompt] = []
    private var advanceScheduled = false
    private var canEdit = true

    var summary: ProtectionSummary { ProtectionSummary(folders: folders, statuses: statuses) }

    /// iOS 没有目录访问能力，传 nil。
    init(access: FolderAccess? = nil,
         persistence: FolderPersistence? = nil,
         authorizer: ProtectionChangeAuthorizing = AllowAllAuthorizer()) {
        self.access = access
        self.persistence = persistence
        self.authorizer = authorizer
        guard access != nil else { return }
        if persistence == nil {
            enqueue(.notice(title: "无法保存设置", message: "找不到保存位置，本次添加的目录在退出后不会保留。"))
        } else {
            load()
        }
        refresh()
    }

    // MARK: - 添加

    private enum Classification {
        case new
        case duplicate(ProtectedFolder)
        case covered(by: ProtectedFolder)
        case covers([ProtectedFolder])
    }

    /// 添加用户选中的目录。用户的选择都会被接受，只有重复和被包含的情况会提示。
    func add(urls: [URL]) {
        guard let access else { return }
        guard canEdit else {
            enqueue(.notice(title: "无法编辑保护目录清单", message: "原清单无法读取，请恢复访问或更新 Vigil 后重新打开。"))
            return
        }
        var notices: [String] = []
        var updated = folders
        var updatedStatuses = statuses

        for url in urls {
            let registered: (identity: FolderIdentity, bookmark: Data)
            do {
                registered = try access.register(url: url)
            } catch {
                notices.append("无法添加「\(url.lastPathComponent)」：\(error.localizedDescription)")
                continue
            }
            let candidate = ProtectedFolder(
                id: UUID(),
                bookmark: registered.bookmark,
                path: registered.identity.path,
                volumeID: registered.identity.volumeID,
                fileID: registered.identity.fileID,
                addedAt: Date()
            )
            switch classify(candidate, among: updated) {
            case .new:
                updated.append(candidate)
                updatedStatuses[candidate.id] = .available
            case .duplicate:
                notices.append("「\(candidate.name)」已在保护清单中。")
            case .covered(let parent):
                notices.append("「\(candidate.name)」已包含在保护目录「\(parent.name)」中，无需单独添加。")
            case .covers(let children):
                enqueue(.merge(newFolder: candidate, childNames: children.map(\.name)))
            }
        }

        if updated != folders { commit(updated, statuses: updatedStatuses) }
        if !notices.isEmpty {
            enqueue(.notice(title: notices.count == 1 ? "没有添加" : "部分目录没有添加",
                            message: notices.joined(separator: "\n")))
        }
    }

    private func classify(_ candidate: ProtectedFolder, among folders: [ProtectedFolder]) -> Classification {
        if let same = folders.first(where: { FolderPathRules.isSameFolder($0, candidate) }) {
            return .duplicate(same)
        }
        if let parent = folders.first(where: { FolderPathRules.contains(parent: $0.path, child: candidate.path) }) {
            return .covered(by: parent)
        }
        let children = folders.filter { FolderPathRules.contains(parent: candidate.path, child: $0.path) }
        return children.isEmpty ? .new : .covers(children)
    }

    private func applyMerge(_ newFolder: ProtectedFolder) {
        // 确认期间清单可能已变化，重新判断一次。
        if folders.contains(where: { FolderPathRules.isSameFolder($0, newFolder) }) { return }
        if folders.contains(where: { FolderPathRules.contains(parent: $0.path, child: newFolder.path) }) { return }
        let childIDs = Set(folders.filter {
            FolderPathRules.contains(parent: newFolder.path, child: $0.path)
        }.map(\.id))
        var updated = folders.filter { !childIDs.contains($0.id) }
        var updatedStatuses = statuses.filter { !childIDs.contains($0.key) }
        updated.append(newFolder)
        updatedStatuses[newFolder.id] = .available
        commit(updated, statuses: updatedStatuses)
    }

    // MARK: - 移出

    /// 只从清单中移出，不触碰磁盘上的目录。
    func remove(_ folder: ProtectedFolder) async {
        guard await authorizer.authorize(.removeFolder) else { return }
        let updated = folders.filter { $0.id != folder.id }
        guard updated.count != folders.count else { return }
        commit(updated, statuses: statuses.filter { $0.key != folder.id })
    }

    // MARK: - 状态刷新

    /// 重新解析每个目录的 bookmark，更新状态。启动、应用回到前台时调用。
    func refresh() {
        guard let access else { return }
        var updated = folders
        var newStatuses: [UUID: FolderStatus] = [:]
        var changed = false

        for index in updated.indices {
            let folder = updated[index]
            switch access.resolve(bookmark: folder.bookmark) {
            case .found(let identity, let refreshedBookmark):
                if let refreshedBookmark {
                    updated[index].bookmark = refreshedBookmark
                    changed = true
                }
                if identity.path != folder.path {
                    updated[index].path = identity.path
                    changed = true
                }
                if identity.volumeID != folder.volumeID || identity.fileID != folder.fileID {
                    updated[index].volumeID = identity.volumeID
                    updated[index].fileID = identity.fileID
                    changed = true
                }
                if !FolderPathRules.samePath(identity.path, folder.path) {
                    newStatuses[folder.id] = .relocated(from: folder.path)
                } else if let existing = statuses[folder.id], case .relocated = existing {
                    newStatuses[folder.id] = existing   // 本次启动内保留“已移动”提示
                } else {
                    newStatuses[folder.id] = .available
                }
            case .missing:
                newStatuses[folder.id] = .missing
            case .inaccessible:
                newStatuses[folder.id] = .inaccessible
            }
        }

        if changed {
            commit(updated, statuses: newStatuses)
        } else {
            statuses = newStatuses
        }
    }

    // MARK: - 提示队列

    /// 用户点了提示上的按钮。`confirmMerge` 只对合并提示有意义。
    func resolveCurrentPrompt(confirmMerge: Bool) {
        guard let prompt = currentPrompt else { return }
        currentPrompt = nil
        if confirmMerge, case .merge(let folder, _) = prompt {
            applyMerge(folder)
        }
        guard !promptQueue.isEmpty else { return }
        // 等上一个提示收起后再显示下一个，否则 SwiftUI 可能不会重新弹出。
        advanceScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self else { return }
            self.advanceScheduled = false
            if self.currentPrompt == nil, !self.promptQueue.isEmpty {
                self.currentPrompt = self.promptQueue.removeFirst()
            }
        }
    }

    private func enqueue(_ prompt: StorePrompt) {
        promptQueue.append(prompt)
        if currentPrompt == nil && !advanceScheduled {
            currentPrompt = promptQueue.removeFirst()
        }
    }

    // MARK: - 持久化

    private func load() {
        guard let persistence else { return }
        do {
            folders = try persistence.load()
        } catch FolderPersistenceError.corrupted(let name) {
            let error = FolderPersistenceError.corrupted(backupName: name)
            enqueue(.notice(title: "无法读取保护目录清单", message: error.localizedDescription))
        } catch {
            canEdit = false
            enqueue(.notice(title: "无法读取保护目录清单", message: error.localizedDescription))
        }
    }

    private func commit(_ updated: [ProtectedFolder], statuses updatedStatuses: [UUID: FolderStatus]) {
        do {
            try persistence?.save(updated)
            folders = updated
            statuses = updatedStatuses
        } catch {
            enqueue(.notice(title: "无法保存保护目录清单", message: error.localizedDescription))
        }
    }
}
