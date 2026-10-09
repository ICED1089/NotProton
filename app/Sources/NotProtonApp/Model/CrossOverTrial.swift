// Accept CodeWeavers' active 14-day trial in addition to the signed paid license.
// We do not modify CrossOver's own preferences, binaries, license, or expiry time.
import Foundation

enum CrossOverTrial {
    static let duration: TimeInterval = 14 * 24 * 60 * 60

    static let defaultPreferences = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Preferences/com.codeweavers.CrossOver.plist")

    static func isActive(
        for install: CrossOverInstall,
        preferences: URL = defaultPreferences,
        now: Date = Date(),
        verifySignature: (URL) -> Bool = isOfficialCrossOver
    ) -> Bool {
        // Only recognize genuine, installed CrossOver bundles, not Wine stand-ins.
        guard CrossOverSource.looksLikeCrossOver(install.bundle) else {
            AppLog.note("trial: installed CrossOver payload is missing")
            return false
        }
        guard verifySignature(install.bundle) else {
            AppLog.note("trial: CodeWeavers app signature not verified")
            return false
        }
        guard let data = try? Data(contentsOf: preferences),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = plist as? [String: Any] else {
            AppLog.note("trial: CrossOver preferences not readable")
            return false
        }
        guard let firstRun = values["FirstRunDate"] as? Date else {
            AppLog.note("trial: FirstRunDate not present as a date; trial source needs verification")
            return false
        }

        let elapsed = now.timeIntervalSince(firstRun)
        // FirstRunDate is a local preference, not an authoritative CodeWeavers expiry
        // API. Reject missing, future, and expired dates; don't reset the trial.
        let active = elapsed >= 0 && elapsed < duration
        AppLog.note(active ? "trial: date indicates an active 14-day trial" : "trial: date absent from active window")
        return active
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

        // The actual CodeWeavers Team ID is not publicly documented. Verify
        // the Apple Developer ID signing authority rather than guessing an ID.
        // codesign emits the signer chain to stderr.
        return identity.stderr.split(separator: "\n")
            .contains { line in
                let authority = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return authority.hasPrefix("Authority=Developer ID Application: CodeWeavers")
            }
    }
}
