import Foundation

/// Result of an async git command execution.
struct GitCommandResult {
    let output: Data
    let error: Data
    let exitCode: Int32

    var outputString: String? {
        decodeToString(output)
    }

    var errorString: String? {
        decodeToString(error)
    }

    var succeeded: Bool {
        exitCode == 0
    }

    /// Splits NUL-delimited output into lines, stripping trailing empty elements.
    var nulDelimitedLines: [String] {
        guard let string = outputString else { return [] }
        var lines = string.components(separatedBy: "\0")
        // Strip trailing empty string from final NUL
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }

    private func decodeToString(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        return String(data: data, encoding: .isoLatin1)
    }
}

/// Async git command execution with completion handlers.
/// Designed to replace the NSFileHandle + NSNotification pattern.
@objc(GitAsyncCommand)
@objcMembers
final class GitAsyncCommand: NSObject {

    private static let environmentKeysToStrip = [
        "MallocStackLogging",
        "MallocStackLoggingNoCompact",
        "NSZombieEnabled"
    ]

    // MARK: - Swift API (completion handler)

    /// Executes a git command asynchronously.
    /// - Parameters:
    ///   - arguments: Git command arguments (without "git" itself)
    ///   - workingDirectory: Directory to run in
    ///   - completion: Called on main thread with result
    static func run(
        arguments: [String],
        workingDirectory: String,
        completion: @escaping (GitCommandResult) -> Void
    ) {
        guard let gitPath = PBGitBinary.path() else {
            let result = GitCommandResult(
                output: Data(),
                error: "Git binary not found".data(using: .utf8) ?? Data(),
                exitCode: -1
            )
            DispatchQueue.main.async { completion(result) }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.environment = sanitizedEnvironment()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Use a background queue for the process
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
            } catch {
                let result = GitCommandResult(
                    output: Data(),
                    error: "Failed to launch: \(error.localizedDescription)".data(using: .utf8) ?? Data(),
                    exitCode: -1
                )
                DispatchQueue.main.async { completion(result) }
                return
            }

            // Read output (blocks until process completes)
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let result = GitCommandResult(
                output: outputData,
                error: errorData,
                exitCode: process.terminationStatus
            )

            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Executes multiple git commands in parallel, calling completion when all finish.
    /// - Parameters:
    ///   - commands: Array of argument arrays
    ///   - workingDirectory: Directory to run in
    ///   - completion: Called on main thread with results in same order as commands
    static func runParallel(
        commands: [[String]],
        workingDirectory: String,
        completion: @escaping ([GitCommandResult]) -> Void
    ) {
        guard !commands.isEmpty else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let group = DispatchGroup()
        var results = [GitCommandResult?](repeating: nil, count: commands.count)
        let lock = NSLock()

        for (index, args) in commands.enumerated() {
            group.enter()
            run(arguments: args, workingDirectory: workingDirectory) { result in
                lock.lock()
                results[index] = result
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(results.compactMap { $0 })
        }
    }

    // MARK: - ObjC API

    /// ObjC-compatible async execution.
    /// - Parameters:
    ///   - arguments: Git command arguments
    ///   - workingDirectory: Directory to run in
    ///   - completion: Called on main thread with output string (nil on error), error string, and exit code
    @objc(runWithArguments:workingDirectory:completion:)
    static func objc_run(
        arguments: [String],
        workingDirectory: String,
        completion: @escaping (_ output: String?, _ error: String?, _ exitCode: Int32) -> Void
    ) {
        run(arguments: arguments, workingDirectory: workingDirectory) { result in
            completion(result.outputString, result.errorString, result.exitCode)
        }
    }

    /// ObjC-compatible parallel execution.
    /// Results are delivered as an array of dictionaries with keys: "output", "error", "exitCode"
    @objc(runParallelCommands:workingDirectory:completion:)
    static func objc_runParallel(
        commands: [[String]],
        workingDirectory: String,
        completion: @escaping ([[String: Any]]) -> Void
    ) {
        runParallel(commands: commands, workingDirectory: workingDirectory) { results in
            let dicts = results.map { result -> [String: Any] in
                var dict: [String: Any] = ["exitCode": NSNumber(value: result.exitCode)]
                if let output = result.outputString {
                    dict["output"] = output
                }
                if let error = result.errorString {
                    dict["error"] = error
                }
                return dict
            }
            completion(dicts)
        }
    }

    // MARK: - Private

    private static func sanitizedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for key in environmentKeysToStrip {
            environment.removeValue(forKey: key)
        }
        return environment
    }
}

// MARK: - Async/Await API (Swift 5.5+)

extension GitAsyncCommand {

    /// Executes a git command using Swift concurrency.
    @available(macOS 10.15, *)
    static func run(
        arguments: [String],
        workingDirectory: String
    ) async -> GitCommandResult {
        await withCheckedContinuation { continuation in
            run(arguments: arguments, workingDirectory: workingDirectory) { result in
                continuation.resume(returning: result)
            }
        }
    }

    /// Executes multiple git commands concurrently using Swift concurrency.
    @available(macOS 10.15, *)
    static func runParallel(
        commands: [[String]],
        workingDirectory: String
    ) async -> [GitCommandResult] {
        await withCheckedContinuation { continuation in
            runParallel(commands: commands, workingDirectory: workingDirectory) { results in
                continuation.resume(returning: results)
            }
        }
    }
}
