import Foundation

/// 用户选择的一个受保护目录。目录本身留在原位置，这里只保存对它的引用。
struct ProtectedFolder: Identifiable, Codable, Equatable {
    let id: UUID
    /// security-scoped bookmark：重启后恢复访问，目录被移动后仍可跟踪。
    var bookmark: Data
    /// 最近一次确认的路径（已展开符号链接）。显示用，阶段 2 也作为扩展的策略输入。
    var path: String
    /// 卷 UUID 与目录编号：判重、识别移动，同样供后续扩展使用。
    var volumeID: String?
    var fileID: UInt64?
    var addedAt: Date

    var name: String { (path as NSString).lastPathComponent }
}

/// 目录的当前可用状态。只在运行时计算，不落盘。
enum FolderStatus: Equatable {
    case available
    /// 本次启动发现目录已移动，已跟踪到新位置。
    case relocated(from: String)
    /// 目录已删除、已进废纸篓，或所在磁盘未连接。
    case missing
    /// 目录存在但无法读取，或已被同名文件替换。
    case inaccessible

    var isUsable: Bool {
        switch self {
        case .available, .relocated: return true
        case .missing, .inaccessible: return false
        }
    }

    var label: String {
        switch self {
        case .available: return "可用"
        case .relocated: return "已移动"
        case .missing: return "找不到"
        case .inaccessible: return "无法访问"
        }
    }

    var note: String? {
        switch self {
        case .available: return nil
        case .relocated(let from): return "已跟踪到新位置，原位置：\(from)"
        case .missing: return "目录已被删除，或所在磁盘未连接。"
        case .inaccessible: return "目录无法读取，或已被文件替换。"
        }
    }
}

/// 本机保护状态摘要，供设备页和保护目录页共用。
/// 阶段 1 没有保护扩展，所以不会出现「保护中」。阶段 2 接入扩展后在这里增加状态。
struct ProtectionSummary: Equatable {
    enum State: Equatable {
        case notConfigured
        case configuredInactive
        case someUnavailable(Int)
    }

    let folderCount: Int
    let state: State

    init(folders: [ProtectedFolder], statuses: [UUID: FolderStatus]) {
        folderCount = folders.count
        let unavailable = folders.filter { !(statuses[$0.id]?.isUsable ?? false) }.count
        if folders.isEmpty {
            state = .notConfigured
        } else if unavailable > 0 {
            state = .someUnavailable(unavailable)
        } else {
            state = .configuredInactive
        }
    }

    var statusText: String {
        switch state {
        case .notConfigured: return "未配置保护目录"
        case .configuredInactive: return "已配置，保护未启用"
        case .someUnavailable(let n): return "已配置，保护未启用（\(n) 个目录不可用）"
        }
    }

    var explanation: String {
        switch state {
        case .notConfigured:
            return "尚未选择要保护的目录。"
        case .configuredInactive:
            return "目录已记录，但保护扩展尚未运行，当前不会拦截任何操作。"
        case .someUnavailable(let n):
            return "有 \(n) 个目录当前不可用，详见下方列表。保护扩展尚未运行，当前不会拦截任何操作。"
        }
    }

    var countText: String { folderCount == 0 ? "未配置" : "\(folderCount) 个" }

    var symbol: String {
        switch state {
        case .notConfigured: return "shield.slash"
        case .configuredInactive: return "shield"
        case .someUnavailable: return "exclamationmark.shield"
        }
    }
}
