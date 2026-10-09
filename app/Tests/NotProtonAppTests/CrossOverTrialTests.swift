import Foundation
import Testing

@testable import NotProtonApp

@Suite("CrossOver trial")
struct CrossOverTrialTests {
    private static func fixture() throws -> (bundle: URL, preferences: URL, cleanup: () -> Void) {
        let base = URL.temporaryDirectory.appending(path: "np-trial-\(UUID().uuidString)")
        let bundle = base.appending(path: "CrossOver.app")
        let root = SupportPaths.crossOverRoot(inBundle: bundle)
        try FileManager.default.createDirectory(
            at: root.appending(path: "lib/wine"), withIntermediateDirectories: true
        )
        return (bundle, base.appending(path: "preferences.plist"), {
            try? FileManager.default.removeItem(at: base)
        })
    }

    private static func write(_ firstRun: Date?, to file: URL) throws {
        var contents: [String: Any] = ["OtherPreference": true]
        if let firstRun { contents["FirstRunDate"] = firstRun }
        let data = try PropertyListSerialization.data(
            fromPropertyList: contents, format: .xml, options: 0
        )
        try data.write(to: file)
    }

    private static func install(_ bundle: URL) -> CrossOverInstall {
        CrossOverInstall(bundle: bundle, releaseVersion: "26.3", support: .unreadable)
    }

    @Test("An official bundle with an active trial is accepted")
    func acceptsActiveTrial() throws {
        let f = try Self.fixture()
        defer { f.cleanup() }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try Self.write(now.addingTimeInterval(-3 * 24 * 60 * 60), to: f.preferences)
        #expect(CrossOverTrial.isActive(
            for: Self.install(f.bundle), preferences: f.preferences, now: now,
            verifySignature: { _ in true }
        ))
    }

    @Test("The trial expires at 14 days and never accepts future dates")
    func rejectsExpiredOrFutureTrial() throws {
        let f = try Self.fixture()
        defer { f.cleanup() }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for elapsed in [CrossOverTrial.duration, CrossOverTrial.duration + 1, -1] {
            try Self.write(now.addingTimeInterval(-elapsed), to: f.preferences)
            #expect(!CrossOverTrial.isActive(
                for: Self.install(f.bundle), preferences: f.preferences, now: now,
                verifySignature: { _ in true }
            ))
        }
    }

    @Test("Missing start date, unsigned app, and absent preference file are refused")
    func failsClosed() throws {
        let f = try Self.fixture()
        defer { f.cleanup() }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!CrossOverTrial.isActive(
            for: Self.install(f.bundle), preferences: f.preferences, now: now,
            verifySignature: { _ in true }
        ))
        try Self.write(nil, to: f.preferences)
        #expect(!CrossOverTrial.isActive(
            for: Self.install(f.bundle), preferences: f.preferences, now: now,
            verifySignature: { _ in true }
        ))
        try Self.write(now.addingTimeInterval(-3600), to: f.preferences)
        #expect(!CrossOverTrial.isActive(
            for: Self.install(f.bundle), preferences: f.preferences, now: now,
            verifySignature: { _ in false }
        ))
    }
}
