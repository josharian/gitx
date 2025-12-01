import Foundation

// MARK: - Service Protocols
//
// These protocols define the boundaries for extracting services from PBGitRepository.
// During the Swift migration, PBGitRepository will be decomposed into smaller,
// testable services that conform to these protocols.
//
// Migration strategy:
// 1. Define protocols (this file)
// 2. Have PBGitRepository conform to protocols via extensions
// 3. Extract implementations into separate service classes
// 4. Inject services into PBGitRepository
// 5. Eventually, consumers use services directly

// MARK: - GitCheckoutService

/// Service for checkout operations (checkout, merge, cherry-pick, rebase).
protocol GitCheckoutService: AnyObject {
    /// Checks out the given ref (branch, tag, or commit).
    /// - Parameter ref: The ref to checkout.
    /// - Throws: GitXError if checkout fails.
    func checkout(_ ref: any PBGitRefish) throws

    /// Merges the given ref into the current branch.
    /// - Parameter ref: The ref to merge.
    /// - Throws: GitXError if merge fails.
    func merge(_ ref: any PBGitRefish) throws

    /// Cherry-picks the given commit onto the current branch.
    /// - Parameter ref: The commit to cherry-pick.
    /// - Throws: GitXError if cherry-pick fails.
    func cherryPick(_ ref: any PBGitRefish) throws

    /// Rebases the current branch onto the given upstream.
    /// - Parameters:
    ///   - branch: The branch to rebase (usually current branch).
    ///   - upstream: The upstream ref to rebase onto.
    /// - Throws: GitXError if rebase fails.
    func rebase(_ branch: any PBGitRefish, onto upstream: any PBGitRefish) throws
}

// MARK: - GitBranchService

/// Service for branch and tag operations.
protocol GitBranchService: AnyObject {
    /// Creates a new branch at the given ref.
    /// - Parameters:
    ///   - name: The name of the new branch.
    ///   - ref: The ref to create the branch at.
    /// - Throws: GitXError if creation fails.
    func createBranch(named name: String, at ref: any PBGitRefish) throws

    /// Creates a new tag at the given ref.
    /// - Parameters:
    ///   - name: The name of the new tag.
    ///   - message: Optional tag message (for annotated tags).
    ///   - ref: The ref to create the tag at.
    /// - Throws: GitXError if creation fails.
    func createTag(named name: String, message: String?, at ref: any PBGitRefish) throws

    /// Deletes the given ref (branch or tag).
    /// - Parameter ref: The ref to delete.
    /// - Throws: GitXError if deletion fails.
    func delete(_ ref: PBGitRef) throws

    /// Returns all branches (local and remote).
    var branches: [PBGitRevSpecifier] { get }

    /// Returns all remotes.
    var remotes: [String] { get }
}

// MARK: - GitRefService

/// Service for ref operations (lookup, validation, parsing).
protocol GitRefService: AnyObject {
    /// Returns the SHA for the given ref.
    /// - Parameter ref: The ref to resolve.
    /// - Returns: The SHA string, or nil if not found.
    func sha(for ref: PBGitRef) -> String?

    /// Returns the commit for the given ref.
    /// - Parameter ref: The ref to resolve.
    /// - Returns: The commit, or nil if not found.
    func commit(for ref: PBGitRef) -> PBGitCommit?

    /// Checks if the ref name is valid.
    /// - Parameter name: The ref name to validate.
    /// - Returns: True if the name is valid.
    func isValidRefName(_ name: String) -> Bool

    /// Checks if the ref exists in the repository.
    /// - Parameter ref: The ref to check.
    /// - Returns: True if the ref exists.
    func refExists(_ ref: PBGitRef) -> Bool

    /// Parses a symbolic reference.
    /// - Parameter ref: The symbolic ref to parse (e.g., "HEAD").
    /// - Returns: The resolved ref name.
    func parseSymbolicRef(_ ref: String) -> String?

    /// Returns a ref by name.
    /// - Parameter name: The ref name to look up.
    /// - Returns: The ref, or nil if not found.
    func ref(named name: String) -> PBGitRef?

    /// All refs in the repository, keyed by SHA.
    var refs: [String: [PBGitRef]] { get }

    /// Reloads refs from the repository.
    func reloadRefs()
}

// MARK: - GitStatusService

/// Service for repository status operations.
protocol GitStatusService: AnyObject {
    /// The current HEAD ref specifier.
    var headRef: PBGitRevSpecifier? { get }

    /// The SHA of the current HEAD.
    var headSHA: String { get }

    /// The commit at HEAD.
    var headCommit: PBGitCommit? { get }

    /// The current branch ref.
    var currentBranch: PBGitRevSpecifier? { get set }

    /// The working directory path.
    var workingDirectory: String { get }

    /// Whether this is a bare repository.
    var isBareRepository: Bool { get }

    /// Whether the repository has uncommitted changes.
    var hasChanges: Bool { get }

    /// Refreshes the repository status.
    func refresh()
}

// MARK: - GitCommandService

/// Low-level service for executing git commands.
protocol GitCommandService: AnyObject {
    /// Executes a git command and returns the output.
    /// - Parameters:
    ///   - arguments: The command arguments (without "git").
    ///   - input: Optional input to pipe to the command.
    ///   - environment: Optional environment variables to add.
    /// - Returns: The command output.
    /// - Throws: GitXError if the command fails.
    func execute(_ arguments: [String], input: String?, environment: [String: String]?) throws -> String

    /// Executes a git command and returns a file handle for streaming output.
    /// - Parameter arguments: The command arguments (without "git").
    /// - Returns: A file handle for reading the output.
    func executeStreaming(_ arguments: [String]) -> FileHandle?
}

// MARK: - GitHistoryService

/// Service for commit history operations.
protocol GitHistoryService: AnyObject {
    /// Returns the commit for the given SHA.
    /// - Parameter sha: The SHA to look up.
    /// - Returns: The commit, or nil if not found.
    func commit(forSHA sha: String) -> PBGitCommit?

    /// Checks if two SHAs are on the same branch.
    /// - Parameters:
    ///   - sha1: The first SHA.
    ///   - sha2: The second SHA.
    /// - Returns: True if they're on the same branch.
    func areOnSameBranch(_ sha1: String, _ sha2: String) -> Bool

    /// Checks if a SHA is on the HEAD branch.
    /// - Parameter sha: The SHA to check.
    /// - Returns: True if the SHA is on the HEAD branch.
    func isOnHeadBranch(_ sha: String) -> Bool
}
