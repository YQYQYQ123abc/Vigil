import Combine
import SwiftUI

private enum SectionTab: String, Hashable {
    case devices = "设备"
    case alerts = "异常"
    case history = "记录"
    case settings = "设置"
}

/// 外观模式（设置 → 显示）：跟随系统时不强制，浅色 / 深色强制对应配色
private enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 语言（设置 → 显示 → 语言）：目前仅建立入口，选择暂不生效
private enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "简体中文"
    case english = "English"

    var id: String { rawValue }
}

private struct DemoDevice: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let status: String
    var isLocal = false
}

private struct DemoEvent: Identifiable {
    let id: String
    let deviceID: String
    let title: String
    let time: String
    let detail: String
    var needsRecovery = false
    var needsReview = false

    var isPending: Bool { needsReview || needsRecovery }

    var status: String {
        if needsRecovery { return "待恢复" }
        if needsReview { return "待查看" }
        return id == "permissions" ? "已恢复" : id == "open" ? "已查看" : "已记录"
    }
}

private final class DemoSession: ObservableObject {
    @Published var selectedTab: SectionTab = .devices
    @Published var events = [
        DemoEvent(id: "permissions", deviceID: "mac", title: "文件保护已暂停", time: "今天 14:32",
                  detail: "完全磁盘访问权限已关闭。恢复权限后，受保护目录才能重新拦截文件操作。", needsRecovery: true),
        DemoEvent(id: "open", deviceID: "mac", title: "文件打开请求已拒绝", time: "今天 14:18",
                  detail: "Finder 尝试打开受保护目录中的「合同草稿.pdf」。请求已拒绝。", needsReview: true),
        DemoEvent(id: "enabled", deviceID: "mac", title: "已开启文件保护", time: "今天 09:00",
                  detail: "已将两个现有目录纳入保护范围。")
    ]
    @Published var alertPath = NavigationPath()
    @Published var verificationEvent: String?

}

struct ContentView: View {
    @StateObject private var session = DemoSession()
    @AppStorage("vigil.appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("vigil.language") private var language: AppLanguage = .simplifiedChinese
    @ObservedObject private var folderStore: ProtectedFolderStore

    /// macOS 注入真实的保护目录清单；iOS 没有本机保护，使用空清单。
    init(folderStore: ProtectedFolderStore = ProtectedFolderStore()) {
        _folderStore = ObservedObject(wrappedValue: folderStore)
    }

    private var devices: [DemoDevice] {
        [
            DemoDevice(id: "mac", name: "MacBook Pro", symbol: "laptopcomputer",
                       status: macStatusText,
                       isLocal: isDesktop),
            DemoDevice(id: "pc", name: "工作电脑", symbol: "desktopcomputer", status: "离线，最后在线 昨天 18:24")
        ]
    }

    /// 电脑端：本机状态来自真实配置，不受示例事件影响。手机端：仍是示例设备。
    private var macStatusText: String {
        if isDesktop { return folderStore.summary.statusText }
        return session.events.contains(where: \.needsRecovery) ? "保护已暂停" : "保护中"
    }

    private var isDesktop: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    private var pendingEvents: [DemoEvent] { session.events.filter(\.isPending) }

    var body: some View {
        TabView(selection: $session.selectedTab) {
            Tab("设备", systemImage: "laptopcomputer", value: .devices) {
                NavigationStack {
                    List {
                        Section {
                            Label {
                                Text(isDesktop ? "本机保护目录为真实配置，其他设备和事件为示例" : "当前展示示例设备和事件")
                            } icon: {
                                Image(systemName: "eye")
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 9, weight: .bold))
                                            .offset(x: 5, y: 4)
                                    }
                            }
                            .foregroundStyle(.secondary)
                        }
                        if isDesktop, let local = devices.first {
                            Section("本机") { deviceRow(local) }
                        }
                        Section(isDesktop ? "其他设备" : "我的设备") {
                            ForEach(devices.filter { !$0.isLocal }) { deviceRow($0) }
                        }
                    }
                    .navigationTitle("设备")
                }
            }
            Tab("异常", systemImage: "exclamationmark.triangle", value: .alerts) {
                NavigationStack(path: $session.alertPath) {
                    eventList(pendingEvents, title: "异常")
                }
            }
            .badge(pendingEvents.count)

            Tab("记录", systemImage: "clock.arrow.circlepath", value: .history) {
                NavigationStack { eventList(session.events, title: "记录") }
            }
            Tab("设置", systemImage: "gearshape", value: .settings) {
                NavigationStack {
                    List {
                        Section("账号") {
                            settingsRow("设备隔离", icon: "lock.shield",
                                        detail: "仅本机可见的设备不会在其他设备上显示。")
                        }
                        Section("显示") {
                            NavigationLink {
                                List {
                                    Picker("外观", selection: $appearanceMode) {
                                        ForEach(AppearanceMode.allCases) { mode in
                                            Text(mode.rawValue).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.inline)
                                    .labelsHidden()
                                }
                                .navigationTitle("外观")
                            } label: {
                                HStack {
                                    Label("外观", systemImage: "circle.lefthalf.filled")
                                    Spacer()
                                    Text(appearanceMode.rawValue)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            NavigationLink {
                                List {
                                    Picker("语言", selection: $language) {
                                        ForEach(AppLanguage.allCases) { option in
                                            Text(option.rawValue).tag(option)
                                        }
                                    }
                                    .pickerStyle(.inline)
                                    .labelsHidden()
                                }
                                .navigationTitle("语言")
                            } label: {
                                HStack {
                                    Label("语言", systemImage: "globe")
                                    Spacer()
                                    Text(language.rawValue)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if isDesktop {
                            Section("安全") {
                                settingsRow("身份验证", icon: "touchid",
                                            detail: "系统身份验证与二级密码将在接入本机保护后启用。")
                                settingsRow("证据保留", icon: "archivebox",
                                            detail: "原型尚未采集截图、录像或人像。")
                            }
                        } else {
                            Section("提醒") {
                                settingsRow("通知偏好", icon: "bell", detail: "原型尚未接入推送。")
                            }
                        }
                    }
                    .navigationTitle("设置")
                }
            }
        }
        #if os(macOS)
        .tabViewStyle(.sidebarAdaptable)
        .frame(minWidth: 680, minHeight: 460)
        #endif
        .preferredColorScheme(appearanceMode.colorScheme)
        .confirmationDialog("恢复演示保护", isPresented: Binding(
            get: { session.verificationEvent != nil },
            set: { if !$0 { session.verificationEvent = nil } }
        ), titleVisibility: .visible, presenting: session.verificationEvent) { id in
            Button("模拟验证通过") { restoreDemoProtection(for: id) }
            Button("取消", role: .cancel) { session.verificationEvent = nil }
        } message: { _ in
            Text("此操作只更新示例状态。原型尚未接入系统身份验证和二级密码。")
        }
    }

    private func deviceRow(_ device: DemoDevice) -> some View {
        NavigationLink {
            List {
                Section("保护状态") {
                    #if os(macOS)
                    if device.isLocal {
                        LocalProtectionStatusRow(store: folderStore)
                        ProtectedFoldersLink(store: folderStore)
                    } else {
                        Label(device.status, systemImage: "shield")
                    }
                    #else
                    Label(device.status, systemImage: "shield")
                    if device.id == "mac" {
                        LabeledContent("保护目录", value: "2 个")
                    }
                    #endif
                }
                let related = pendingEvents.filter { $0.deviceID == device.id }
                if !related.isEmpty {
                    Section("待处理异常") {
                        ForEach(related) { event in
                            Button {
                                session.alertPath = NavigationPath()
                                session.alertPath.append(event.id)
                                session.selectedTab = .alerts
                            } label: {
                                eventRow(event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(device.name)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                    Text(device.status).font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: device.symbol)
            }
        }
    }

    private func eventList(_ items: [DemoEvent], title: String) -> some View {
        List(items) { event in
            NavigationLink(value: event.id) { eventRow(event) }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("没有待处理异常", systemImage: "checkmark.shield")
            }
        }
        .navigationTitle(title)
        .navigationDestination(for: String.self) { id in
            eventDetail(id)
        }
    }

    private func eventRow(_ event: DemoEvent) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                Text("\(event.time) · 示例").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.status)
                .font(.subheadline)
                .foregroundStyle(event.needsRecovery ? Color.orange : Color.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func eventDetail(_ id: String) -> some View {
        if let event = session.events.first(where: { $0.id == id }) {
            List {
                Section {
                    LabeledContent("设备", value: devices.first { $0.id == event.deviceID }?.name ?? "未知设备")
                    LabeledContent("时间", value: event.time)
                    LabeledContent("状态", value: event.status)
                }
                Section("经过（示例）") {
                    Text(event.detail)
                    if id == "permissions", !event.needsRecovery {
                        Text("已在演示中恢复保护。").foregroundStyle(.secondary)
                    }
                }
                if event.isPending {
                    Section {
                        if event.needsReview {
                            Button("标记已查看") {
                                if let index = session.events.firstIndex(where: { $0.id == id }) {
                                    session.events[index].needsReview = false
                                }
                            }
                        }
                        if event.needsRecovery {
                            if isDesktop {
                                Button("演示恢复保护") { session.verificationEvent = id }
                            } else {
                                Text("请在 MacBook Pro 上恢复磁盘访问权限。")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(event.title)
        }
    }

    private func settingsRow(_ title: String, icon: String, detail: String) -> some View {
        NavigationLink {
            List { Text(detail) }
                .navigationTitle(title)
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private func restoreDemoProtection(for id: String) {
        guard let index = session.events.firstIndex(where: { $0.id == id }) else { return }
        session.events[index].needsRecovery = false
        session.verificationEvent = nil
    }
}
