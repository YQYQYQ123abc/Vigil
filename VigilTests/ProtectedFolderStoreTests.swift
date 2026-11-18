// 可选：在 Xcode 中新建 Unit Testing Bundle（目标 Vigil-macOS）后，把此文件加入测试目标。
import Foundation
import Testing
@testable import Vigil_macOS

/// 用字典模拟磁盘，不访问真实文件系统。
private final class FakeAccess: FolderAccess {
    var existing: Set<String> = []
    var redirects: [String: String] = [:]      // 旧路径 → 新路径（模拟目录被移动）
    private var ids: [String: UInt64] = [:]

    private func id(for path: String) -> UInt64 {
        if let v = ids[path] { return v }
        let v = UInt64(ids.count + 1); ids[path] = v; return v
    }

    func register(url: URL) throws -> (identity: FolderIdentity, bookmark: Data) {
        existing.insert(url.path)
        return (FolderIdentity(path: url.path, volumeID: "V", fileID: id(for: url.path)), Data(url.path.utf8))
    }

    func resolve(bookmark: Data) -> FolderResolveResult {
        let original = String(decoding: bookmark, as: UTF8.self)
        let path = redirects[original] ?? original
        guard existing.contains(path) || redirects[original] != nil else { return .missing }
        return .found(FolderIdentity(path: path, volumeID: "V", fileID: id(for: original)), refreshedBookmark: nil)
    }
}

private final class MemoryPersistence: FolderPersistence {
    var stored: [ProtectedFolder] = []
    func load() throws -> [ProtectedFolder] { stored }
    func save(_ folders: [ProtectedFolder]) throws { stored = folders }
}

@MainActor
struct ProtectedFolderStoreTests {
    let access = FakeAccess()
    let memory = MemoryPersistence()
    func makeStore() -> ProtectedFolderStore {
        ProtectedFolderStore(access: access, persistence: memory)
    }
    func url(_ p: String) -> URL { URL(fileURLWithPath: p) }

    @Test func addsFolderAndReportsInactive() {
        let store = makeStore()
        store.add(urls: [url("/Users/a/Docs")])
        #expect(store.folders.count == 1)
        #expect(store.summary.state == .configuredInactive)
        #expect(memory.stored.count == 1)
    }

    @Test func rejectsDuplicateAndExplains() {
        let store = makeStore()
        store.add(urls: [url("/Users/a/Docs")])
        store.add(urls: [url("/users/a/docs/")])   // 大小写与结尾斜杠不同
        #expect(store.folders.count == 1)
        if case .notice = store.currentPrompt {} else { Issue.record("应出现重复提示") }
    }

    @Test func childOfProtectedFolderIsCovered() {
        let store = makeStore()
        store.add(urls: [url("/Users/a/Docs")])
        store.add(urls: [url("/Users/a/Docs/Contracts")])
        #expect(store.folders.count == 1)
    }

    @Test func siblingWithSamePrefixIsNotCovered() {
        let store = makeStore()
        store.add(urls: [url("/Users/a/Docs")])
        store.add(urls: [url("/Users/a/Docs-old")])
        #expect(store.folders.count == 2)
    }

    @Test func parentAsksToMergeAndReplacesChildren() {
        let store = makeStore()
        store.add(urls: [url("/Users/a/Docs/A"), url("/Users/a/Docs/B")])
        store.add(urls: [url("/Users/a/Docs")])
        if case .merge = store.currentPrompt {} else { Issue.record("应出现合并提示") }
        #expect(store.folders.count == 2)           // 确认前不变
        store.resolveCurrentPrompt(confirmMerge: true)
        #expect(store.folders.map(\.path) == ["/Users/a/Docs"])
    }

    @Test func cancellingMergeKeepsList() {
        let store = makeStore()
        store.add(urls: [url("/Users/a/Docs/A")])
        store.add(urls: [url("/Users/a/Docs")])
        store.resolveCurrentPrompt(confirmMerge: false)
        #expect(store.folders.map(\.path) == ["/Users/a/Docs/A"])
    }

    @Test func removeOnlyChangesList() async {
        let store = makeStore()
        store.add(urls: [url("/Users/a/Docs")])
        await store.remove(store.folders[0])
        #expect(store.folders.isEmpty)
        #expect(memory.stored.isEmpty)
        #expect(access.existing.contains("/Users/a/Docs"))   // 目录本身未被触碰
    }

    @Test func restoresAfterRestart() {
        makeStore().add(urls: [url("/Users/a/Docs")])
        let restarted = makeStore()
        #expect(restarted.folders.count == 1)
        #expect(restarted.statuses[restarted.folders[0].id] == .available)
    }

    @Test func detectsMissingAndRelocated() {
        let store = makeStore()
        store.add(urls: [url("/Users/a/Docs"), url("/Users/a/Pics")])
        access.existing.remove("/Users/a/Docs")
        access.existing.insert("/Users/a/Photos")
        access.redirects["/Users/a/Pics"] = "/Users/a/Photos"
        store.refresh()
        let byName = Dictionary(uniqueKeysWithValues: store.folders.map { ($0.name, store.statuses[$0.id]) })
        #expect(byName["Docs"] == .missing)
        #expect(byName["Photos"] == .relocated(from: "/Users/a/Pics"))
        #expect(store.summary.state == .someUnavailable(1))
    }

    @Test func corruptedFileIsBackedUpNotOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("ProtectedFolders.json")
        try Data("not json".utf8).write(to: file)
        #expect(throws: FolderPersistenceError.self) {
            try JSONFolderPersistence(fileURL: file).load()
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(leftovers.contains { $0.contains("corrupt") })
    }
}
