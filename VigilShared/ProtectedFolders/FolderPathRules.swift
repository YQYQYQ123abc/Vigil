import Foundation

/// 目录判重与包含关系。macOS 默认卷不区分大小写，所以这里按不区分大小写比较。
enum FolderPathRules {
    static func normalized(_ path: String) -> String {
        var s = path.precomposedStringWithCanonicalMapping.lowercased()
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s
    }

    static func samePath(_ a: String, _ b: String) -> Bool {
        normalized(a) == normalized(b)
    }

    /// `child` 是否位于 `parent` 之内（不含相同路径）。
    static func contains(parent: String, child: String) -> Bool {
        let p = normalized(parent)
        let c = normalized(child)
        guard p != c else { return false }
        let prefix = p == "/" ? "/" : p + "/"
        return c.hasPrefix(prefix)
    }

    /// 同一个目录：卷与目录编号都相同，或路径相同。
    static func isSameFolder(_ a: ProtectedFolder, _ b: ProtectedFolder) -> Bool {
        if let av = a.volumeID, let bv = b.volumeID, let af = a.fileID, let bf = b.fileID,
           av == bv, af == bf {
            return true
        }
        return samePath(a.path, b.path)
    }
}
