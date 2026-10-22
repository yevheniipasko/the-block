import SwiftUI

@main
struct TheBlockApp: App {

    @State private var appModule = AppModule()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await appModule.start() }
        }
    }

}
