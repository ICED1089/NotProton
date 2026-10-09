// Accept CodeWeavers' active 14-day trial in addition to the signed paid license.
// We do not modify CrossOver's own preferences, binaries, license, or expiry time.
import Foundation

enum CrossOverTrial {
    static let duration: TimeInterval = 14 * 24 * 60 * 60

    // CodeWeavers' Apple Developer ID team. Never trust an arbitrary app with the right name.
    static let codeWeaversTeamID = "9C6B7X7Z8E"

    static let defaultPreferences = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Preferences/com.codeweavers.CrossOver.plist")

    static func isActive(
        for install: CrossOverInstall,
        preferences: URL = defaultPreferences,
        now: Date = Date(),
        verifySignature: (URL) -> Bool = isOfficialCrossOver
    ) -> Bool {
        // Only recognize genuine, installed CrossOver bundles, not Wine stand-ins.
        guard CrossOverSource.looksLikeCrossOver(install.bundle),
              verifySignature(install.bundle),
              let data = try? Data(contentsOf: preferences),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = plist as? [String: Any],
              let firstRun = values["FirstRunDate"] as? Date
        else { return false }

        let elapsed = now.timeIntervalSince(firstRun)
        // FirstRunDate is a local preference, not an authoritative CodeWeavers expiry
        // API. Reject missing, future, and expired dates; don't reset the trial.
        return elapsed >= 0 && elapsed < duration
    }

    static func isActive(forBuild build: RunnerBuild) -> Bool {
        // A cloned runner must still match an installed, supported, unexpired source.
        CrossOverSource.discover().contains { install in
            guard case .supported(let installedBuild) = install.support,
                  installedBuild.id == build.id
            else { return false }
            return isActive(for: install)
        }
    }

    static func isOfficialCrossOver(_ bundle: URL) -> Bool {
        let path = bundle.path(percentEncoded: false)
        guard let verified = try? Shell.run("/usr/bin/codesign", [
            "--verify", "--strict", path,
        ]), verified.succeeded,
              let identity = try? Shell.run("/usr/bin/codesign", [
                  "--display", "--verbose=4", path,
              ]), identity.succeeded
        else { return false }

        // codesign emits identity metadata on stderr.
        return identity.stderr.split(separator: "\n")
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                == "TeamIdentifier=\(codeWeaversTeamID)" }
    }
}
