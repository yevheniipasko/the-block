import SwiftUI

@main
struct TheBlockApp: App {

    @State private var appModule = AppModule()

    var body: some Scene {
        WindowGroup {
            InventoryRouterView(router: appModule.router)
                .task { await appModule.start() }
        }
    }

}
