import Testing
@testable import LocalFlowCore

@Test func comparesSemanticVersions() {
    #expect(AppVersion("1.1.0")! > AppVersion("1.0.9")!)
    #expect(AppVersion("2.0.0")! > AppVersion("1.99.99")!)
    #expect(AppVersion("1.0.0")! == AppVersion("1.0.0")!)
}

@Test func acceptsGitHubVersionTags() {
    #expect(AppVersion(gitHubTag: "v1.2.3") == AppVersion("1.2.3"))
    #expect(AppVersion(gitHubTag: "1.2.3") == AppVersion("1.2.3"))
}

@Test func rejectsInvalidVersions() {
    #expect(AppVersion("1.2") == nil)
    #expect(AppVersion("latest") == nil)
    #expect(AppVersion(gitHubTag: "release") == nil)
}

@Test func identifiesAvailableUpdate() {
    #expect(UpdateDecision(current: "1.0.0", latestTag: "v1.1.0").isUpdateAvailable)
    #expect(!UpdateDecision(current: "1.1.0", latestTag: "v1.1.0").isUpdateAvailable)
    #expect(!UpdateDecision(current: "1.2.0", latestTag: "v1.1.0").isUpdateAvailable)
}
