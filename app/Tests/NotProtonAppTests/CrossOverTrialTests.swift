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

@Suite("Trial-aware license verdict")
struct TrialAwareLicenseTests {
    private let install = CrossOverInstall(
        bundle: URL(filePath: "/tmp/fake-CrossOver.app"),
        releaseVersion: nil, support: .unreadable
    )
    private let paid = CrossOverLicense.Status(
        licensed: false, detail: CrossOverLicense.notActivated,
        diagnostic: "no paid license"
    )

    @Test("An active trial is treated as activated throughout setup")
    func trialAccepted() {
        let status = CrossOverLicense.check(
            for: install, paidCheck: { _ in paid }, trialCheck: { _ in true }
        )
        #expect(status.licensed)
        #expect(status.detail == "CrossOver trial is active.")
    }

    @Test("An inactive trial does not hide the paid-license failure")
    func inactiveTrialDenied() {
        let status = CrossOverLicense.check(
            for: install, paidCheck: { _ in paid }, trialCheck: { _ in false }
        )
        #expect(!status.licensed)
        #expect(status.diagnostic == paid.diagnostic)
    }

    @Test("A valid purchased license is accepted without consulting trial state")
    func paidLicenseUnchanged() {
        var calledTrial = false
        let status = CrossOverLicense.check(
            for: install,
            paidCheck: { _ in CrossOverLicense.Status(
                licensed: true, detail: "CrossOver is activated.",
                diagnostic: "valid signed license"
            ) },
            trialCheck: { _ in calledTrial = true; return false }
        )
        #expect(status.licensed)
        #expect(!calledTrial)
    }
}

@Suite("CrossOver runtime provenance")
struct CrossOverRuntimeProvenanceTests {
    @Test("An ad-hoc or unknown bundle without pinned runtime hashes is refused")
    func unknownRuntimeIsRefused() throws {
        let root = URL.temporaryDirectory.appending(path: "np-provenance-\(UUID().uuidString)")
        let bundle = root.appending(path: "CrossOver.app")
        defer { try? FileManager.default.removeItem(at: root) }
        let wine = SupportPaths.crossOverRoot(inBundle: bundle).appending(path: "lib/wine")
        try FileManager.default.createDirectory(at: wine, withIntermediateDirectories: true)
        #expect(!CrossOverTrial.isRecognizedCrossOver(bundle))
    }
}
