import Foundation

// MARK: - GitRefish Protocol (Swift-native version)

/// Protocol for objects that can be used as git ref specifiers.
/// Both PBGitRef (refs/heads/master) and PBGitCommit (SHA) conform to this.
///
/// This is the Swift-native equivalent of the ObjC `PBGitRefish` protocol.
/// The method signatures match the ObjC protocol exactly.
///
/// Note: PBGitCommit and PBGitRef already conform to the ObjC PBGitRefish protocol
/// via the bridging header. This Swift protocol provides type-safe usage in Swift code.
protocol GitRefish {
    /// The full name of the ref ("refs/heads/master") or the full SHA.
    /// Used in git commands.
    func refishName() -> String

    /// A more user-friendly version: "master" or a short SHA.
    func shortName() -> String

    /// A short name for the type (e.g., "branch", "tag", "commit", "stash").
    func refishType() -> String
}

// Note: PBGitCommit and PBGitRef already implement these methods,
// so they implicitly conform to GitRefish. We don't need explicit extensions.

// MARK: - GitXError (Swift Error Type)

/// Swift-native error type for GitX operations.
/// Provides a more ergonomic API than NSError while maintaining ObjC compatibility.
enum GitXError: Error, LocalizedError, CustomNSError {
    case commandFailed(command: String, exitCode: Int32, stderr: String?)
    case invalidRepository(path: String)
    case invalidRef(name: String)
    case gitNotFound(suggestion: String?)
    case invalidArguments(reason: String)
    case operationFailed(description: String)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, _):
            return "Git command failed with exit code \(exitCode): \(command)"
        case .invalidRepository(let path):
            return "\(path) does not appear to be a git repository"
        case .invalidRef(let name):
            return "Invalid ref: \(name)"
        case .gitNotFound:
            return "Git binary not found"
        case .invalidArguments(let reason):
            return "Invalid arguments: \(reason)"
        case .operationFailed(let description):
            return description
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .commandFailed(_, _, let stderr):
            return stderr
        case .gitNotFound(let suggestion):
            return suggestion
        default:
            return nil
        }
    }

    // MARK: - CustomNSError (ObjC compatibility)

    static var errorDomain: String {
        "PBGitRepositoryErrorDomain"
    }

    var errorCode: Int {
        switch self {
        case .commandFailed:
            return Int(PBGitErrorCode.commandFailed.rawValue)
        case .invalidRepository:
            return Int(PBGitErrorCode.invalidRepository.rawValue)
        case .invalidRef:
            return Int(PBGitErrorCode.invalidRef.rawValue)
        case .gitNotFound:
            return Int(PBGitErrorCode.gitNotFound.rawValue)
        case .invalidArguments:
            return Int(PBGitErrorCode.invalidArguments.rawValue)
        case .operationFailed:
            return Int(PBGitErrorCode.commandFailed.rawValue)
        }
    }

    var errorUserInfo: [String: Any] {
        var info: [String: Any] = [:]
        if let description = errorDescription {
            info[NSLocalizedDescriptionKey] = description
        }
        if let suggestion = recoverySuggestion {
            info[NSLocalizedRecoverySuggestionErrorKey] = suggestion
        }
        return info
    }

    // MARK: - Conversion from NSError

    /// Creates a GitXError from an NSError if it's in the GitX error domain.
    init?(nsError: NSError) {
        guard nsError.domain == "PBGitRepositoryErrorDomain" else {
            return nil
        }

        let description = nsError.localizedDescription
        let suggestion = nsError.localizedRecoverySuggestion

        switch PBGitErrorCode(rawValue: nsError.code) {
        case .commandFailed:
            let command = nsError.userInfo["GitCommand"] as? String ?? "unknown"
            let exitCode = (nsError.userInfo["ExitCode"] as? NSNumber)?.int32Value ?? -1
            self = .commandFailed(command: command, exitCode: exitCode, stderr: suggestion)
        case .invalidRepository:
            self = .invalidRepository(path: description)
        case .invalidRef:
            self = .invalidRef(name: description)
        case .gitNotFound:
            self = .gitNotFound(suggestion: suggestion)
        case .invalidArguments:
            self = .invalidArguments(reason: description)
        default:
            self = .operationFailed(description: description)
        }
    }
}

// MARK: - Error Domain Constants

/// Error domain for GitX operations.
/// Kept for ObjC compatibility - matches PBGitRepositoryErrorDomain.
let GitXErrorDomain = "PBGitRepositoryErrorDomain"
