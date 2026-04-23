//
//  FramedApp.swift
//  Framed
//
//  Created by Victor Noagbodji on 3/28/26.
//

import SwiftUI

@main
struct FramedApp: App {
    @StateObject private var model = FramedMenuModel()
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        MenuBarExtra("Framed", systemImage: "aspectratio") {
            FramedMenuView(model: model, updater: updater)
        }
        .menuBarExtraStyle(.menu)
    }
}
