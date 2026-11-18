//
//  Vigil_macOSApp.swift
//  Vigil-macOS
//
//  Created by yangqin on 11/18/26.
//

import AppKit
import SwiftUI

@main
struct Vigil_macOSApp: App {
    @StateObject private var folderStore = ProtectedFolderStore.makeMac()

    var body: some Scene {
        WindowGroup {
            ContentView(folderStore: folderStore)
                .modifier(StorePromptAlert(store: folderStore))
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    folderStore.refresh()
                }
        }
    }
}
