import Foundation

@objcMembers
@objc(GitCommandRunner)
final class GitCommandRunner: NSObject {
    static let shared = GitCommandRunner()

    private let environmentKeysToStrip = [
        "MallocStackLogging",
        "MallocStackLoggingNoCompact",
        "NSZombieEnabled"
    ]

    private override init() {
        super.init()
    }

    func run(arguments anyArguments: [Any],
             repository: PBGitRepository,
             input: String?,
             environment environmentOverrides: [String: Any]?,
             error: NSErrorPointer) -> String? {
        let argumentStrings = coerceArguments(anyArguments)
        guard !argumentStrings.isEmpty else {
            assignError(code: .invalidArguments,
                        description: "Git command arguments cannot be empty",
                        recoverySuggestion: nil,
                        errorPointer: error)
            return nil
        }

        guard let gitPath = PBGitBinary.path(), !gitPath.isEmpty else {
            let recovery = PBGitBinary.notFoundError()
            assignError(code: .gitNotFound,
                        description: "Git binary not found",
                        recoverySuggestion: recovery,
                        errorPointer: error)
            return nil
        }

        let workingDirectory = repository.workingDirectory()
        let environment = mergedEnvironment(with: environmentOverrides)

        if UserDefaults.standard.bool(forKey: "Show Debug Messages") {
            let joined = argumentStrings.joined(separator: " ")
            NSLog("Executing git command: %@ %@ in %@", gitPath, joined, workingDirectory ?? "(nil)")
        }

        var exitStatus: Int32 = -1
        var stderrOutput: NSString?
        guard var output = PBEasyPipe.outputForCommand(
            gitPath,
            withArgs: argumentStrings,
            inDir: workingDirectory,
            byExtendingEnvironment: environment,
            inputString: input,
            retValue: &exitStatus,
            standardError: &stderrOutput
        ), exitStatus == 0 else {
            let suggestion = stderrOutput as String?
            let message = exitStatus == -1
                ? "Git command execution failed"
                : "Git command failed with exit code \(exitStatus)"
            let joined = argumentStrings.joined(separator: " ")
            var userInfo: [String: Any] = [
                NSLocalizedDescriptionKey: message,
                "GitCommand": "Command: git \(joined)",
                "ExitCode": NSNumber(value: exitStatus)
            ]
            if let suggestion, !suggestion.isEmpty {
                userInfo[NSLocalizedRecoverySuggestionErrorKey] = suggestion
            }
            assignError(code: .commandFailed, userInfo: userInfo, errorPointer: error)
            return nil
        }

        if output.hasSuffix("\n") {
            output.removeLast()
        }

        return output
    }

    private func coerceArguments(_ arguments: [Any]) -> [String] {
        var result: [String] = []
        result.reserveCapacity(arguments.count)
        for argument in arguments {
            switch argument {
            case let string as String:
                result.append(string)
            case let stringConvertible as CustomStringConvertible:
                result.append(stringConvertible.description)
            default:
                continue
            }
        }
        return result
    }

    private func mergedEnvironment(with overrides: [String: Any]?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for key in environmentKeysToStrip {
            environment.removeValue(forKey: key)
        }

        guard let overrides else {
            return environment
        }

        for (key, valueAny) in overrides {
            let value: String
            if let string = valueAny as? String {
                value = string
            } else if let convertible = valueAny as? CustomStringConvertible {
                value = convertible.description
            } else {
                value = "\(valueAny)"
            }
            environment[key] = value
        }

        return environment
    }

    private func assignError(code: PBGitErrorCode,
                             description: String,
                             recoverySuggestion: String?,
                             errorPointer: NSErrorPointer) {
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: description
        ]
        if let recoverySuggestion {
            userInfo[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion
        }
        assignError(code: code, userInfo: userInfo, errorPointer: errorPointer)
    }

    private func assignError(code: PBGitErrorCode,
                             userInfo: [String: Any],
                             errorPointer: NSErrorPointer) {
        guard let errorPointer else { return }
        errorPointer.pointee = NSError(
            domain: "PBGitRepositoryErrorDomain",
            code: Int(code.rawValue),
            userInfo: userInfo
        )
    }
}
