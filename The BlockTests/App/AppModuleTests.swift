import Testing
@testable import The_Block

@MainActor
struct AppModuleTests {

    @Test("AppModule wires the real data stack and loads the bundled inventory")
    func resolvesAndLoads() async {
        let appModule = AppModule()

        await appModule.start()

        #expect(appModule.repository.loadState == .loaded)
        #expect(appModule.repository.vehicles.count == 200)
    }

    @Test("Repository is shared: every access returns the same instance")
    func repositoryIsSingleInstance() {
        let appModule = AppModule()

        #expect(appModule.repository === appModule.repository)
    }

}
