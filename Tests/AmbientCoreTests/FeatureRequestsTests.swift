import Foundation
import Testing
@testable import AmbientCore

@Suite struct FeatureRequestsTests {
    @Test func opensTheBoardTaggedWithTheAppAndVersion() {
        #expect(FeatureRequests.url(version: "0.4.0").absoluteString == "https://yaml.cafe/requests/?from=app&v=0.4.0")
    }

    @Test func defaultsToTheRunningVersion() {
        #expect(FeatureRequests.url().absoluteString == "https://yaml.cafe/requests/?from=app&v=\(AmbientVersion.current)")
    }

    @Test func websiteIsTheHomepage() {
        #expect(FeatureRequests.website.absoluteString == "https://yaml.cafe/")
    }
}
