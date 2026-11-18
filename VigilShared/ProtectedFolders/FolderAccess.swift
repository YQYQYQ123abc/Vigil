import Foundation

/// 一个目录在某一时刻的身份信息。
struct FolderIdentity: Equatable {
    var path: String
    var volumeID: String?
    var fileID: UInt64?
}

enum FolderResolveResult {
    case found(FolderIdentity, refreshedBookmark: Data?)
    case missing
    case inaccessible
}

/// 平台相关的目录访问能力。macOS 用 security-scoped bookmark 实现；iOS 不提供。
protocol FolderAccess {
    /// 为用户刚选中的目录生成身份信息与 bookmark。
    func register(url: URL) throws -> (identity: FolderIdentity, bookmark: Data)
    /// 重启后或定期检查时，根据 bookmark 找回目录。
    func resolve(bookmark: Data) -> FolderResolveResult
}

/// 敏感操作的授权入口。阶段 3 接入本机验证与二级密码，现在直接放行。
enum SensitiveAction {
    case removeFolder
}

protocol ProtectionChangeAuthorizing {
    func authorize(_ action: SensitiveAction) async -> Bool
}

struct AllowAllAuthorizer: ProtectionChangeAuthorizing {
    func authorize(_ action: SensitiveAction) async -> Bool { true }
}
