import Foundation

public let kGitXTagType: NSString = "tag"
public let kGitXBranchType: NSString = "branch"
public let kGitXRemoteType: NSString = "remote"
public let kGitXRemoteBranchType: NSString = "remote branch"

public let kGitXTagRefPrefix: NSString = "refs/tags/"
public let kGitXBranchRefPrefix: NSString = "refs/heads/"
public let kGitXRemoteRefPrefix: NSString = "refs/remotes/"

@objcMembers
@objc(PBGitRef)
final class PBGitRef: NSObject, PBGitRefish {
    @objc let ref: String

    @objc(refFromString:)
    class func refFromString(_ string: String) -> PBGitRef {
        PBGitRef(string: string)
    }

    @objc(initWithString:)
    init(string: String) {
        self.ref = string
        super.init()
    }

    override init() {
        self.ref = ""
        super.init()
    }

    var tagName: String? {
        guard isTag else { return nil }
        return shortName()
    }

    var branchName: String? {
        guard isBranch else { return nil }
        return shortName()
    }

    var remoteName: String? {
        guard isRemote else { return nil }
        let parts = ref.split(separator: "/")
        guard parts.count > 2 else { return nil }
        return String(parts[2])
    }

    var remoteBranchName: String? {
        guard isRemoteBranch, let remoteName else { return nil }
        let short = shortName()
        guard short.count > remoteName.count + 1 else { return nil }
        let index = short.index(short.startIndex, offsetBy: remoteName.count + 1)
        return String(short[index...])
    }

    var type: String? {
        if isBranch { return "head" }
        if isTag { return "tag" }
        if isRemote { return "remote" }
        return nil
    }

    var isBranch: Bool {
        ref.hasPrefix(kGitXBranchRefPrefix as String)
    }

    var isTag: Bool {
        ref.hasPrefix(kGitXTagRefPrefix as String)
    }

    var isRemote: Bool {
        ref.hasPrefix(kGitXRemoteRefPrefix as String)
    }

    var isRemoteBranch: Bool {
        guard isRemote else { return false }
        return ref.split(separator: "/").count > 3
    }

    func remoteRef() -> PBGitRef? {
        guard let remoteName else { return nil }
        return PBGitRef(string: (kGitXRemoteRefPrefix as String) + remoteName)
    }

    @objc(isEqualToRef:)
    func isEqual(to other: PBGitRef?) -> Bool {
        guard let other else { return false }
        return ref == other.ref
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PBGitRef else { return false }
        return ref == other.ref
    }

    override var hash: Int {
        ref.hash
    }

    // MARK: - <PBGitRefish>

    func refishName() -> String {
        ref
    }

    func shortName() -> String {
        guard let type else {
            return ref
        }

        let prefixLength = type.count + 7
        guard ref.count > prefixLength else {
            return ref
        }

        let index = ref.index(ref.startIndex, offsetBy: prefixLength)
        return String(ref[index...])
    }

    func refishType() -> String? {
        if isBranch { return kGitXBranchType as String }
        if isTag { return kGitXTagType as String }
        if isRemoteBranch { return kGitXRemoteBranchType as String }
        if isRemote { return kGitXRemoteType as String }
        return nil
    }
}
