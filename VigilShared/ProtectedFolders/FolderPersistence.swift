import Foundation

protocol FolderPersistence {
    func load() throws -> [ProtectedFolder]
    func save(_ folders: [ProtectedFolder]) throws
}

enum FolderPersistenceError: LocalizedError {
    /// 清单文件无法解析。原文件已改名保留，没有被覆盖。
    case corrupted(backupName: String)
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "清单版本为 \(version)，请使用支持该版本的 Vigil 打开。"
        case .corrupted(let name):
            return "保护目录清单无法读取，原文件已另存为「\(name)」。当前清单为空。"
        }
    }
}

/// 把清单存成带版本号的 JSON。阶段 2 需要让扩展读取时，再迁到 App Group。
struct JSONFolderPersistence: FolderPersistence {
    static let currentVersion = 1

    let fileURL: URL

    private struct VersionHeader: Decodable {
        let version: Int
    }

    private struct Envelope: Codable {
        var version: Int
        var folders: [ProtectedFolder]
    }

    static func defaultFileURL() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return base.appendingPathComponent("Vigil", isDirectory: true)
            .appendingPathComponent("ProtectedFolders.json")
    }

    func load() throws -> [ProtectedFolder] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let envelope: Envelope
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let header = try decoder.decode(VersionHeader.self, from: data)
            guard header.version == Self.currentVersion else {
                throw FolderPersistenceError.unsupportedVersion(header.version)
            }
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch let error as FolderPersistenceError {
            throw error
        } catch {
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("ProtectedFolders.corrupt-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: fileURL, to: backup)
            throw FolderPersistenceError.corrupted(backupName: backup.lastPathComponent)
        }
        return envelope.folders
    }

    func save(_ folders: [ProtectedFolder]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Envelope(version: Self.currentVersion, folders: folders))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
