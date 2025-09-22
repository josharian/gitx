import Foundation

@objc(PBEasyPipe)
@objcMembers
final class PBEasyPipe: NSObject {
    private static let debugPreferenceKey = "Show Debug Messages"
    private static let environmentKeysToStrip = [
        "MallocStackLogging",
        "MallocStackLoggingNoCompact",
        "NSZombieEnabled"
    ]

    // MARK: - Public API (ObjC exposed)

    @objc(handleForCommand:withArgs:)
    class func handleForCommand(_ command: String, withArgs arguments: [String]) -> FileHandle? {
        return handleForCommand(command, withArgs: arguments, inDir: nil)
    }

    @objc(taskForCommand:withArgs:inDir:)
    class func taskForCommand(_ command: String, withArgs arguments: [String], inDir directory: String?) -> Process? {
        guard let process = makeProcess(
            executablePath: command,
            arguments: arguments,
            workingDirectory: directory,
            environmentExtras: nil,
            combineOutputPipes: true
        ) else {
            return nil
        }

        logIfNeeded(command: command, arguments: arguments, directory: directory)
        return process
    }

    @objc(handleForCommand:withArgs:inDir:)
    class func handleForCommand(_ command: String, withArgs arguments: [String], inDir directory: String?) -> FileHandle? {
        guard let process = taskForCommand(command, withArgs: arguments, inDir: directory) else {
            return nil
        }

        guard let pipe = process.standardOutput as? Pipe else {
            return nil
        }

        do {
            try launch(process)
        } catch {
            return nil
        }

        return pipe.fileHandleForReading
    }

    @objc(outputForCommand:withArgs:inDir:retValue:)
    class func outputForCommand(_ command: String,
                                withArgs arguments: [String],
                                inDir directory: String?,
                                retValue: UnsafeMutablePointer<Int32>?) -> String? {
        return outputForCommand(
            command,
            withArgs: arguments,
            inDir: directory,
            byExtendingEnvironment: nil,
            inputString: nil,
            retValue: retValue,
            standardError: nil
        )
    }

    @objc(outputForCommand:withArgs:inDir:inputString:retValue:)
    class func outputForCommand(_ command: String,
                                withArgs arguments: [String],
                                inDir directory: String?,
                                inputString: String?,
                                retValue: UnsafeMutablePointer<Int32>?) -> String? {
        return outputForCommand(
            command,
            withArgs: arguments,
            inDir: directory,
            byExtendingEnvironment: nil,
            inputString: inputString,
            retValue: retValue,
            standardError: nil
        )
    }

    @objc(outputForCommand:withArgs:inDir:byExtendingEnvironment:inputString:retValue:)
    class func outputForCommand(_ command: String,
                                withArgs arguments: [String],
                                inDir directory: String?,
                                byExtendingEnvironment environment: [String: String]?,
                                inputString: String?,
                                retValue: UnsafeMutablePointer<Int32>?) -> String? {
        return outputForCommand(
            command,
            withArgs: arguments,
            inDir: directory,
            byExtendingEnvironment: environment,
            inputString: inputString,
            retValue: retValue,
            standardError: nil
        )
    }

    @objc(outputForCommand:withArgs:inDir:byExtendingEnvironment:inputString:retValue:standardError:)
    class func outputForCommand(_ command: String,
                                withArgs arguments: [String],
                                inDir directory: String?,
                                byExtendingEnvironment environment: [String: String]?,
                                inputString: String?,
                                retValue: UnsafeMutablePointer<Int32>?,
                                standardError: AutoreleasingUnsafeMutablePointer<NSString?>?) -> String? {
        guard let result = runProcess(
            executablePath: command,
            arguments: arguments,
            workingDirectory: directory,
            environmentExtras: environment,
            input: inputString
        ) else {
            retValue?.pointee = -1
            standardError?.pointee = nil
            return nil
        }

        retValue?.pointee = result.terminationStatus

        if var stderrString = decodeToString(result.standardError) {
            if stderrString.hasSuffix("\n") {
                stderrString.removeLast()
            }
            standardError?.pointee = stderrString as NSString
        } else {
            standardError?.pointee = nil
        }

        guard var output = decodeToString(result.standardOutput) else {
            return nil
        }

        if output.hasSuffix("\n") {
            output.removeLast()
        }

        return output
    }

    @objc(outputForCommand:withArgs:inDir:)
    class func outputForCommand(_ command: String,
                                withArgs arguments: [String],
                                inDir directory: String?) -> String? {
        var status: Int32 = 0
        let string = outputForCommand(
            command,
            withArgs: arguments,
            inDir: directory,
            retValue: &status
        )
        return string
    }

    @objc(outputForCommand:withArgs:)
    class func outputForCommand(_ command: String, withArgs arguments: [String]) -> String? {
        return outputForCommand(command, withArgs: arguments, inDir: nil)
    }

    @objc(gitOutputForArgs:inDir:error:)
    class func gitOutputForArgs(_ args: [String],
                                inDir directory: String?,
                                error: UnsafeMutablePointer<NSError?>?) -> String? {
        guard let gitPath = (NSClassFromString("PBGitBinary") as AnyObject?)?.perform(NSSelectorFromString("path"))?.takeUnretainedValue() as? String else {
            if let errorPointer = error {
                let userInfo: [String: Any] = [NSLocalizedDescriptionKey: "Git binary not found"]
                errorPointer.pointee = NSError(
                    domain: "PBGitRepositoryErrorDomain",
                    code: 1004,
                    userInfo: userInfo
                )
            }
            return nil
        }

        var exitCode: Int32 = 0
        var stderrOutput: NSString?
        let output = outputForCommand(
            gitPath,
            withArgs: args,
            inDir: directory,
            byExtendingEnvironment: nil,
            inputString: nil,
            retValue: &exitCode,
            standardError: &stderrOutput
        )

        if exitCode != 0 {
            if let errorPointer = error {
                let description = "Git command failed with exit code \(exitCode)"
                var userInfo: [String: Any] = [
                    NSLocalizedDescriptionKey: description,
                    "GitArgs": args,
                    "ExitCode": NSNumber(value: exitCode)
                ]
                if let stderr = stderrOutput as String?, !stderr.isEmpty {
                    userInfo[NSLocalizedRecoverySuggestionErrorKey] = stderr
                }
                errorPointer.pointee = NSError(
                    domain: "PBGitRepositoryErrorDomain",
                    code: 1001,
                    userInfo: userInfo
                )
            }
            return nil
        }

        return output
    }

    // MARK: - Private helpers

    private class func launch(_ process: Process) throws {
        if #available(macOS 10.13, *) {
            try process.run()
        } else {
            process.launch()
        }
    }

    private class func makeProcess(executablePath: String,
                                    arguments: [String],
                                    workingDirectory: String?,
                                    environmentExtras: [String: String]?,
                                    combineOutputPipes: Bool) -> Process? {
        let process = Process()
        process.launchPath = executablePath
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        if let directory = workingDirectory {
            process.currentDirectoryPath = directory
        }

        process.environment = sanitizedEnvironment(merging: environmentExtras)

        if combineOutputPipes {
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
        }

        return process
    }

    private class func runProcess(executablePath: String,
                                  arguments: [String],
                                  workingDirectory: String?,
                                  environmentExtras: [String: String]?,
                                  input: String?) -> (standardOutput: Data, standardError: Data, terminationStatus: Int32)? {
        guard let process = makeProcess(
            executablePath: executablePath,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environmentExtras: environmentExtras,
            combineOutputPipes: false
        ) else {
            return nil
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var inputData: Data?
        if let input = input {
            inputData = input.data(using: .utf8)
            let inputPipe = Pipe()
            process.standardInput = inputPipe
        }

        logIfNeeded(command: executablePath, arguments: arguments, directory: workingDirectory)

        do {
            try launch(process)
        } catch {
            return nil
        }

        if let data = inputData, let inputHandle = (process.standardInput as? Pipe)?.fileHandleForWriting {
            inputHandle.write(data)
            inputHandle.closeFile()
        }

        let standardOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let standardError = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (standardOutput, standardError, process.terminationStatus)
    }

    private class func sanitizedEnvironment(merging extras: [String: String]?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for key in environmentKeysToStrip {
            environment.removeValue(forKey: key)
        }
        if let extras {
            environment.merge(extras) { _, new in new }
        }
        return environment
    }

    private class func decodeToString(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        return String(data: data, encoding: .isoLatin1)
    }

    private class func logIfNeeded(command: String, arguments: [String], directory: String?) {
        guard UserDefaults.standard.bool(forKey: debugPreferenceKey) else {
            return
        }

        let joinedArgs = arguments.joined(separator: " ")
        NSLog("Starting command `%@ %@` in dir %@", command, joinedArgs, directory ?? "(null)")
    }
}
