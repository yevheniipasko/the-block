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
