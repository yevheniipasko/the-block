//
//  TheBlockApp.swift
//  The Block
//
//  App entry point: creates the AppModule and auction ticker and shows the
//  root navigation view.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

@main
struct TheBlockApp: App {

    @State private var appModule = AppModule(launchOptions: LaunchOptions(arguments: ProcessInfo.processInfo.arguments))
    @State private var auctionTicker = AuctionTicker()

    var body: some Scene {
        WindowGroup {
            InventoryRouterView(router: appModule.router, alertCenter: appModule.outbidAlertCenter)
                .environment(auctionTicker)
                .task { await appModule.start() }
                .task { await auctionTicker.run() }
        }
    }

}
