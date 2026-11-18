import AppKit

enum MacFolderAccessError: LocalizedError {
    case notADirectory
    case cannotRead(Int32)

    var errorDescription: String? {
        switch self {
        case .notADirectory: return "所选项目不是目录。"
        case .cannotRead(let code): return "无法读取该目录（错误 \(code)）。"
        }
    }
}

/// 用 security-scoped bookmark 在沙盒内保持对用户所选目录的只读访问。
/// 全程不写入、不移动、不删除用户目录。
struct MacFolderAccess: FolderAccess {
    private static let bookmarkOptions: URL.BookmarkCreationOptions = [
        .withSecurityScope, .securityScopeAllowOnlyReadAccess
    ]

    func register(url: URL) throws -> (identity: FolderIdentity, bookmark: Data) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let identity = try Self.identity(of: url)
        let bookmark = try url.bookmarkData(
            options: Self.bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil
        )
        return (identity, bookmark)
    }

    func resolve(bookmark: Data) -> FolderResolveResult {
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            let ns = error as NSError
            let noSuchFile = [CocoaError.fileNoSuchFile.rawValue, CocoaError.fileReadNoSuchFile.rawValue]
            if ns.domain == NSCocoaErrorDomain, noSuchFile.contains(ns.code) { return .missing }
            return .inaccessible
        }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard scoped else { return .inaccessible }

        // 移进废纸篓等同于目录已不在原处。
        if url.path.contains("/.Trash/") { return .missing }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing
        }
        guard isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: url.path),
              let identity = try? Self.identity(of: url) else {
            return .inaccessible
        }

        var refreshed: Data?
        if stale {
            refreshed = try? url.bookmarkData(options: Self.bookmarkOptions,
                                              includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        return .found(identity, refreshedBookmark: refreshed)
    }

    /// 用 stat 读取目录编号（会跟随符号链接），路径展开符号链接后保存。
    private static func identity(of url: URL) throws -> FolderIdentity {
        var info = stat()
        guard stat(url.path, &info) == 0 else { throw MacFolderAccessError.cannotRead(errno) }
        guard (info.st_mode & S_IFMT) == S_IFDIR else { throw MacFolderAccessError.notADirectory }
        let volumeID = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        return FolderIdentity(
            path: url.resolvingSymlinksInPath().standardizedFileURL.path,
            volumeID: volumeID,
            fileID: UInt64(info.st_ino)
        )
    }
}

/// 系统目录选择器：只能选已有目录，不提供「新建文件夹」。
enum FolderPicker {
    static func pick() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "添加保护目录"
        panel.message = "选择要保护的已有目录。目录会留在原位置，其中的文件不会被移动或修改。"
        panel.prompt = "添加"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        return panel.runModal() == .OK ? panel.urls : []
    }
}

extension ProtectedFolderStore {
    static func makeMac() -> ProtectedFolderStore {
        let persistence = JSONFolderPersistence.defaultFileURL().map { JSONFolderPersistence(fileURL: $0) }
        return ProtectedFolderStore(access: MacFolderAccess(), persistence: persistence)
    }
}
