import Foundation

@objcMembers
@objc(PBCommitData)
final class PBCommitData: NSObject {
    @objc dynamic var sha: String?
    @objc dynamic var shortSHA: String?
    @objc dynamic var message: String?
    @objc dynamic var messageSummary: String?
    @objc dynamic var commitDate: Date?
    @objc dynamic var authorName: String?
    @objc dynamic var committerName: String?
    @objc dynamic var parentSHAs: [String]?

    override init() {
        super.init()
    }

    @objc(initWithSha:shortSHA:message:messageSummary:commitDate:authorName:committerName:parentSHAs:)
    init(sha: String?,
         shortSHA: String?,
         message: String?,
         messageSummary: String?,
         commitDate: Date?,
         authorName: String?,
         committerName: String?,
         parentSHAs: [String]?) {
        self.sha = sha
        self.shortSHA = shortSHA
        self.message = message
        self.messageSummary = messageSummary
        self.commitDate = commitDate
        self.authorName = authorName
        self.committerName = committerName
        self.parentSHAs = parentSHAs
        super.init()
    }

    convenience init(copying other: PBCommitData) {
        self.init(sha: other.sha,
                  shortSHA: other.shortSHA,
                  message: other.message,
                  messageSummary: other.messageSummary,
                  commitDate: other.commitDate,
                  authorName: other.authorName,
                  committerName: other.committerName,
                  parentSHAs: other.parentSHAs)
    }

    @objc(parentSHAsFromString:)
    class func parentSHAs(from string: String?) -> [String] {
        guard let string, !string.isEmpty else {
            return []
        }

        let separators = CharacterSet.whitespacesAndNewlines
        return string
            .split(separator: " ")
            .map { substring -> String in
                let trimmed = String(substring).trimmingCharacters(in: separators)
                return trimmed
            }
            .filter { $0.count >= 40 }
    }
}
