import SwiftUI

@main
struct TheBlockApp: App {

    @State private var appModule = AppModule(launchOptions: LaunchOptions(arguments: ProcessInfo.processInfo.arguments))

    var body: some Scene {
        WindowGroup {
            InventoryRouterView(router: appModule.router, alertCenter: appModule.outbidAlertCenter)
                .task { await appModule.start() }
        }
    }

}
