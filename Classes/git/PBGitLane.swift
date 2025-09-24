import Foundation

@objcMembers
@objc(PBGitLane)
final class PBGitLane: NSObject {
    @objc var sha: String?
    @objc let index: Int

    override init() {
        self.index = NSNotFound
        self.sha = nil
        super.init()
    }

    @objc(initWithSHA:)
    convenience init(sha: String?) {
        self.init(index: NSNotFound, sha: sha)
    }

    @objc(initWithIndex:sha:)
    init(index: Int, sha: String?) {
        self.index = index
        self.sha = sha
        super.init()
    }

    func isCommit(_ sha: String) -> Bool {
        guard !sha.isEmpty, let currentSHA = self.sha, !currentSHA.isEmpty else {
            return false
        }
        return currentSHA == sha
    }
}
