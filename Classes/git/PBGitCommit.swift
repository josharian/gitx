import Foundation

public let kGitXCommitType: NSString = "commit"

@objcMembers
@objc(PBGitCommit)
final class PBGitCommit: NSObject, PBGitRefish {
    private weak var repositoryRef: PBGitRepository?
    private var commitData: PBCommitData {
        didSet {
            cachedPatch = nil
        }
    }

    private var cachedPatch: String?

    var sign: Int8 = 0
    var lineInfo: PBGraphCellInfo?

    @objc(initWithRepository:andSHA:)
    init(repository: PBGitRepository?, andSHA sha: String) {
        let initialData = PBCommitData(sha: sha,
                                       shortSHA: PBGitCommit.shortSha(for: sha),
                                       message: nil,
                                       messageSummary: nil,
                                       commitDate: nil,
                                       authorName: nil,
                                       committerName: nil,
                                       parentSHAs: [])
        self.repositoryRef = repository
        self.commitData = initialData
        super.init()
        populateCommitData(using: sha)
    }

    @objc(initWithRepository:andCommitData:)
    init(repository: PBGitRepository?, andCommitData data: PBCommitData) {
        self.repositoryRef = repository
        self.commitData = PBCommitData(copying: data)
        super.init()
    }

    var repository: PBGitRepository? {
        repositoryRef
    }

    var sha: String {
        commitData.sha ?? ""
    }

    // Alias for ObjC/XIB compatibility (key path "realSha" is used in bindings)
    var realSHA: String { sha }
    func realSha() -> String { sha }

    var date: Date {
        commitData.commitDate ?? Date(timeIntervalSince1970: 0)
    }

    func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    var subject: String {
        commitData.messageSummary ?? ""
    }

    var message: String {
        commitData.message ?? ""
    }

    var author: String {
        commitData.authorName ?? ""
    }

    var committer: String {
        commitData.committerName ?? ""
    }

    var details: String {
        ""
    }

    var patch: String {
        if let cachedPatch {
            return cachedPatch
        }

        guard let repo = repository, !realSHA.isEmpty else {
            cachedPatch = ""
            return ""
        }

        guard var output = try? repo.executeGitCommand(["format-patch", "-1", "--stdout", realSHA]) else {
            cachedPatch = ""
            return ""
        }

        if !output.isEmpty {
            output.removeLast()
        }

        let decorated = output + "+GitX"
        cachedPatch = decorated
        return decorated
    }

    var parents: [String] {
        commitData.parentSHAs ?? []
    }

    var refs: NSMutableArray? {
        get {
            let currentSha = sha
            guard !currentSha.isEmpty else { return nil }
            return repository?.refs[currentSha] as? NSMutableArray
        }
        set {
            let currentSha = sha
            guard !currentSha.isEmpty else { return }
            if let newValue {
                repository?.refs[currentSha] = NSMutableArray(array: newValue)
            } else {
                repository?.refs.removeObject(forKey: currentSha)
            }
        }
    }

    func addRef(_ ref: PBGitRef) {
        if let existing = refs {
            existing.add(ref)
            refs = existing
        } else {
            refs = NSMutableArray(object: ref)
        }
    }

    func removeRef(_ ref: Any) {
        guard let existing = refs else {
            return
        }
        existing.remove(ref)
        refs = existing
    }

    func hasRef(_ ref: PBGitRef) -> Bool {
        guard let existing = refs else {
            return false
        }
        for case let existingRef as PBGitRef in existing {
            if existingRef.isEqual(ref) {
                return true
            }
        }
        return false
    }

    @objc(isOnSameBranchAs:)
    func isOnSameBranchAs(_ other: PBGitCommit?) -> Bool {
        guard let other else { return false }
        if other === self {
            return true
        }
        guard let repo = repository else { return false }
        return repo.is(onSameBranch: other.sha, asSHA: sha)
    }

    @nonobjc
    func isOnSameBranch(as other: PBGitCommit?) -> Bool {
        return isOnSameBranchAs(other)
    }

    func isOnHeadBranch() -> Bool {
        guard let head = repository?.headCommit() else {
            return false
        }
        return isOnSameBranchAs(head)
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PBGitCommit else {
            return false
        }
        return other === self
    }

    override var hash: Int {
        sha.hash
    }

    // MARK: - <PBGitRefish>

    func refishName() -> String {
        realSHA
    }

    func shortName() -> String {
        commitData.shortSHA ?? PBGitCommit.shortSha(for: realSHA)
    }

    func refishType() -> String {
        kGitXCommitType as String
    }

    // MARK: - Private

    private func populateCommitData(using sha: String) {
        guard let repo = repository else {
            ensureShaPopulated(with: sha)
            return
        }

        let args = ["show", "--format=%H%n%s%n%B%n%an%n%cn%n%ct%n%P", "--no-patch", sha]
        guard let output = try? repo.executeGitCommand(args) else {
            ensureShaPopulated(with: sha)
            return
        }

        let lines = output.components(separatedBy: "\n")
        guard lines.count >= 7 else {
            ensureShaPopulated(with: sha)
            return
        }

        let shaString = lines[0]
        guard shaString.count >= 40 else {
            ensureShaPopulated(with: sha)
            return
        }

        let messageSummary = lines[1]
        let message = lines[2]
        let authorName = lines[3]
        let committerName = lines[4]
        let timestampString = lines[5]
        let parentSHAsString = lines[6]

        let timestamp = TimeInterval(timestampString) ?? 0
        let parents = PBCommitData.parentSHAs(from: parentSHAsString)
        let data = PBCommitData(sha: shaString,
                                shortSHA: PBGitCommit.shortSha(for: shaString),
                                message: message,
                                messageSummary: messageSummary,
                                commitDate: Date(timeIntervalSince1970: timestamp),
                                authorName: authorName,
                                committerName: committerName,
                                parentSHAs: parents)
        commitData = data
    }

    private func ensureShaPopulated(with sha: String) {
        if commitData.sha == nil {
            commitData.sha = sha
        }
        if commitData.shortSHA == nil {
            commitData.shortSHA = PBGitCommit.shortSha(for: sha)
        }
    }

    private static func shortSha(for sha: String) -> String {
        if sha.count <= 7 {
            return sha
        }
        let index = sha.index(sha.startIndex, offsetBy: 7)
        return String(sha[..<index])
    }
}
