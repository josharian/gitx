import Foundation

/// Specifies a revision or set of revisions for git commands.
/// Can represent a simple ref (branch/tag) or complex parameters (--all, ranges, etc).
@objcMembers
@objc(PBGitRevSpecifier)
final class PBGitRevSpecifier: NSObject, NSCopying, NSSecureCoding {

    // MARK: - Properties

    private var _description: String?
    private let _parameters: [String]
    @objc var workingDirectory: URL?

    @objc private(set) var isSimpleRef: Bool

    @objc var parameters: [String] {
        return _parameters
    }

    // MARK: - Initialization

    @objc(initWithParameters:description:)
    init(parameters: [String], description: String?) {
        self._parameters = parameters
        self._description = description

        // Determine if this is a simple ref
        if parameters.count != 1 {
            self.isSimpleRef = false
        } else {
            let param = parameters[0]
            let specialChars = CharacterSet(charactersIn: "^@{}~:")
            if param.hasPrefix("-") ||
               param.rangeOfCharacter(from: specialChars) != nil ||
               param.contains("..") {
                self.isSimpleRef = false
            } else {
                self.isSimpleRef = true
            }
        }

        super.init()
    }

    @objc(initWithParameters:)
    convenience init(parameters: [String]) {
        self.init(parameters: parameters, description: nil)
    }

    @objc(initWithRef:)
    convenience init(ref: PBGitRef) {
        self.init(parameters: [ref.ref], description: ref.shortName())
    }

    // MARK: - Class Methods

    @objc class func allBranchesRevSpec() -> PBGitRevSpecifier {
        // Using --all here would include refs like refs/notes/commits, which probably isn't what we want.
        return PBGitRevSpecifier(
            parameters: ["--branches", "--remotes", "--tags", "--glob=refs/stash*", "HEAD"],
            description: "All branches"
        )
    }

    @objc class func localBranchesRevSpec() -> PBGitRevSpecifier {
        return PBGitRevSpecifier(
            parameters: ["--branches", "HEAD"],
            description: "Local branches"
        )
    }

    // MARK: - Instance Methods

    @objc var simpleRef: String? {
        guard isSimpleRef else { return nil }
        return _parameters.first
    }

    @objc var ref: PBGitRef? {
        guard isSimpleRef, let simpleRef = simpleRef else { return nil }
        return PBGitRef.refFromString(simpleRef)
    }

    @objc var hasPathLimiter: Bool {
        return _parameters.contains("--")
    }

    @objc var title: String {
        let titleValue: String

        if description == "HEAD" {
            titleValue = "detached HEAD"
        } else if isSimpleRef {
            titleValue = ref?.shortName() ?? description
        } else if description.hasPrefix("-S") {
            titleValue = String(description.dropFirst(2))
        } else if description.hasPrefix("HEAD -- ") {
            titleValue = String(description.dropFirst(8))
        } else if description.hasPrefix("-- ") {
            titleValue = String(description.dropFirst(3))
        } else {
            titleValue = description
        }

        return "\u{201C}\(titleValue)\u{201D}"
    }

    @objc func isAllBranchesRev() -> Bool {
        return self == PBGitRevSpecifier.allBranchesRevSpec()
    }

    @objc func isLocalBranchesRev() -> Bool {
        return self == PBGitRevSpecifier.localBranchesRevSpec()
    }

    // MARK: - Description

    @objc override var description: String {
        get {
            if let desc = _description {
                return desc
            }
            return _parameters.joined(separator: " ")
        }
        set {
            _description = newValue
        }
    }

    // MARK: - Equality

    @objc(isEqual:)
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PBGitRevSpecifier else { return false }

        if isSimpleRef != other.isSimpleRef {
            return false
        }

        if isSimpleRef {
            return _parameters.first == other._parameters.first
        }

        return description == other.description
    }

    override var hash: Int {
        if isSimpleRef {
            return _parameters.first?.hash ?? 0
        }
        return description.hash
    }

    // MARK: - NSCopying

    func copy(with zone: NSZone? = nil) -> Any {
        let copy = PBGitRevSpecifier(parameters: _parameters)
        copy._description = _description
        copy.workingDirectory = workingDirectory
        return copy
    }

    // MARK: - NSSecureCoding

    static var supportsSecureCoding: Bool { true }

    @objc required init?(coder: NSCoder) {
        guard let params = coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "Parameters") as? [String] else {
            return nil
        }

        self._parameters = params
        self._description = coder.decodeObject(of: NSString.self, forKey: "Description") as String?

        // Recompute isSimpleRef
        if params.count != 1 {
            self.isSimpleRef = false
        } else {
            let param = params[0]
            let specialChars = CharacterSet(charactersIn: "^@{}~:")
            if param.hasPrefix("-") ||
               param.rangeOfCharacter(from: specialChars) != nil ||
               param.contains("..") {
                self.isSimpleRef = false
            } else {
                self.isSimpleRef = true
            }
        }

        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(_description, forKey: "Description")
        coder.encode(_parameters, forKey: "Parameters")
    }
}
