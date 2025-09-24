import Foundation

@objc(GitRepoFinder)
@objcMembers
final class GitRepoFinder: NSObject {
    @objc(workDirForURL:)
    class func workDir(for fileURL: URL) -> URL? {
        guard fileURL.isFileURL else {
            return nil
        }

        let gitPath = PBGitBinary.path() ?? "/usr/bin/git"
        var exitCode: Int32 = 0
        let output = PBEasyPipe.outputForCommand(
            gitPath,
            withArgs: ["rev-parse", "--show-toplevel"],
            inDir: fileURL.path,
            retValue: &exitCode
        )

        guard exitCode == 0, let trimmed = trimmedPath(from: output) else {
            return nil
        }

        return URL(fileURLWithPath: trimmed)
    }

    @objc(gitDirForURL:)
    class func gitDir(for fileURL: URL) -> URL? {
        guard fileURL.isFileURL else {
            return nil
        }

        let gitPath = PBGitBinary.path() ?? "/usr/bin/git"
        var exitCode: Int32 = 0
        let output = PBEasyPipe.outputForCommand(
            gitPath,
            withArgs: ["rev-parse", "--git-dir"],
            inDir: fileURL.path,
            retValue: &exitCode
        )

        guard exitCode == 0, let trimmed = trimmedPath(from: output) else {
            return nil
        }

        let absolutePath: String
        if trimmed.hasPrefix("/") {
            absolutePath = trimmed
        } else {
            let combined = (fileURL.path as NSString).appendingPathComponent(trimmed)
            absolutePath = (combined as NSString).standardizingPath
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: absolutePath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        return URL(fileURLWithPath: absolutePath, isDirectory: true)
    }

    private class func trimmedPath(from output: String?) -> String? {
        guard let raw = output?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }
}
