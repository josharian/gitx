import Foundation

/// Locates and validates the git binary.
/// Thread-safe with cached resolution that respects user preferences.
@objcMembers
@objc(PBGitBinary)
final class PBGitBinary: NSObject {

    // MARK: - Error Types

    private static let errorDomain = "PBGitBinaryErrorDomain"
    private static let errorCodeNotFound = 1

    // MARK: - Cached State

    private static let resolutionQueue = DispatchQueue(label: "xyz.commaok.gitx.git-binary")
    private static var cachedPath: String?
    private static var cachedError: NSError?
    private static var cachedUserConfiguredPath: String?

    // MARK: - Public Class Methods

    /// Returns the path to the git binary, or nil if not found.
    @objc class func path() -> String? {
        return resolveGitPath(nil)
    }

    /// Returns the git version string, or nil if git is not found.
    @objc class func gitVersion() -> String? {
        guard let gitPath = resolveGitPath(nil) else {
            return nil
        }
        return versionForPath(gitPath)
    }

    /// Returns the list of standard locations to search for git.
    @objc class func searchLocations() -> [String] {
        var locations = [
            "/opt/local/bin/git",
            "/sw/bin/git",
            "/opt/git/bin/git",
            "/usr/local/bin/git",
            "/usr/local/git/bin/git",
            "/opt/homebrew/bin/git"
        ]
        locations.append(("~/bin/git" as NSString).expandingTildeInPath)
        locations.append("/usr/bin/git")
        return locations
    }

    /// Returns an error message describing where git was searched.
    @objc class func notFoundError() -> String {
        var message = "Could not find a git binary.\n"
        message += "Please make sure there is a git binary in one of the following locations:\n\n"
        for location in searchLocations() {
            message += "\t\(location)\n"
        }
        return message
    }

    /// Resolves the git path, optionally returning an error.
    /// Thread-safe with caching that respects changes to user preferences.
    @objc class func resolveGitPath(_ error: NSErrorPointer) -> String? {
        var resolvedPath: String?
        var resolvedError: NSError?

        resolutionQueue.sync {
            let currentUserSetting = UserDefaults.standard.string(forKey: "gitExecutable")

            // Invalidate cache if user setting changed
            if (cachedUserConfiguredPath != nil || currentUserSetting != nil) &&
                cachedUserConfiguredPath != currentUserSetting {
                cachedPath = nil
                cachedError = nil
            }
            cachedUserConfiguredPath = currentUserSetting

            // Resolve if not cached
            if cachedPath == nil && cachedError == nil {
                var localError: NSError?
                let resolved = locateGit(&localError)
                cachedPath = resolved
                cachedError = localError
            }

            resolvedPath = cachedPath
            resolvedError = cachedError
        }

        if resolvedPath == nil {
            error?.pointee = resolvedError
        }

        return resolvedPath
    }

    /// Invalidates the cached path, forcing re-resolution on next access.
    @objc class func invalidateCachedPath() {
        resolutionQueue.sync {
            cachedPath = nil
            cachedError = nil
            cachedUserConfiguredPath = nil
        }
    }

    // MARK: - Private Helpers

    private class func locateGit(_ error: NSErrorPointer) -> String? {
        // 1. Check user-configured path
        if let userConfigured = UserDefaults.standard.string(forKey: "gitExecutable") {
            if let resolved = validatedExecutable(at: userConfigured) {
                return resolved
            }
            if !userConfigured.isEmpty {
                NSLog("PBGitBinary: user-configured git path '%@' is invalid; falling back to search paths.", userConfigured)
            }
        }

        // 2. Check GIT_PATH environment variable
        if let envPath = getenv("GIT_PATH") {
            let envCandidate = String(cString: envPath)
            if let resolved = validatedExecutable(at: envCandidate) {
                return resolved
            }
        }

        // 3. Use 'which git'
        if let whichPath = PBEasyPipe.outputForCommand("/usr/bin/which", withArgs: ["git"]) {
            if let resolved = validatedExecutable(at: whichPath) {
                return resolved
            }
        }

        // 4. Check standard locations
        for location in searchLocations() {
            if let resolved = validatedExecutable(at: location) {
                return resolved
            }
        }

        // 5. Try xcrun
        if let xcrunPath = PBEasyPipe.outputForCommand("/usr/bin/xcrun", withArgs: ["-f", "git"]) {
            if let resolved = validatedExecutable(at: xcrunPath) {
                return resolved
            }
        }

        // Not found
        NSLog("PBGitBinary: Could not find a git binary. Checked user defaults, environment, PATH, standard locations, and xcrun.")

        if error != nil {
            let userInfo: [String: Any] = [
                NSLocalizedDescriptionKey: "Could not locate git executable.",
                NSLocalizedRecoverySuggestionErrorKey: notFoundError()
            ]
            error?.pointee = NSError(domain: errorDomain, code: errorCodeNotFound, userInfo: userInfo)
        }

        return nil
    }

    private class func validatedExecutable(at candidate: String) -> String? {
        guard let standardized = sanitizedPath(candidate), !standardized.isEmpty else {
            return nil
        }

        guard FileManager.default.isExecutableFile(atPath: standardized) else {
            return nil
        }

        guard versionForPath(standardized) != nil else {
            return nil
        }

        return standardized
    }

    private class func sanitizedPath(_ candidate: String) -> String? {
        guard !candidate.isEmpty else {
            return nil
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return (trimmed as NSString).standardizingPath
    }

    private class func versionForPath(_ path: String) -> String? {
        guard let standardized = sanitizedPath(path), !standardized.isEmpty else {
            return nil
        }

        guard FileManager.default.isExecutableFile(atPath: standardized) else {
            return nil
        }

        guard var versionOutput = PBEasyPipe.outputForCommand(standardized, withArgs: ["--version"]) else {
            return nil
        }

        versionOutput = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        let prefix = "git version "
        if versionOutput.hasPrefix(prefix) {
            return String(versionOutput.dropFirst(prefix.count))
        }

        return nil
    }
}
