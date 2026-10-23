//
//  AppModuleTests.swift
//  The Block
//
//  Smoke tests for the AppModule composition root: the real data stack loads the
//  bundled inventory and the repository is a single shared instance.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Testing
@testable import The_Block

/// Smoke test for the composition root: AppModule builds the real stack and shares one repository.
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
