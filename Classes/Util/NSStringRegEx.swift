import Foundation
import Darwin

private let regexErrorDomain = "regerror"

@objc extension NSString {
    @objc(substringsMatchingRegularExpression:count:options:ranges:error:)
    func substringsMatchingRegularExpression(_ pattern: String,
                                             count: Int32,
                                             options: Int32,
                                             ranges: AutoreleasingUnsafeMutablePointer<NSArray?>?,
                                             error: NSErrorPointer) -> NSArray? {
        error?.pointee = nil

        var regex = regex_t()
        let compileResult = pattern.withCString { patternPointer -> Int32 in
            regcomp(&regex, patternPointer, options | Int32(REG_EXTENDED))
        }

        guard compileResult == 0 else {
            assignRegexError(code: compileResult, regex: &regex, errorPointer: error)
            regfree(&regex)
            return nil
        }

        defer { regfree(&regex) }

        let string = self as String
        return string.withCString { pointer -> NSArray? in
            let matchCapacity = count < 0 ? 0 : Int(count) + 1
            let pmatch: UnsafeMutablePointer<regmatch_t>?

            if matchCapacity > 0 {
                pmatch = UnsafeMutablePointer<regmatch_t>.allocate(capacity: matchCapacity)
            } else {
                pmatch = nil
            }

            defer { pmatch?.deallocate() }

            let execResult = regexec(
                &regex,
                pointer,
                count < 0 ? 0 : numericCast(matchCapacity),
                pmatch,
                0
            )

            guard execResult == 0 else {
                if execResult != REG_NOMATCH {
                    assignRegexError(code: execResult, regex: &regex, errorPointer: error)
                }
                return nil
            }

            if count == -1 {
                return NSArray(object: self)
            }

            guard let pmatch else {
                return NSArray()
            }

            let matches = NSMutableArray(capacity: matchCapacity)
            let rangeValues = NSMutableArray(capacity: matchCapacity)

            for index in 0..<matchCapacity {
                let match = pmatch[index]
                if match.rm_so == -1 || match.rm_eo == -1 {
                    break
                }

                let location = Int(match.rm_so)
                let end = Int(match.rm_eo)
                let length = end - location

                guard let substring = NSString(
                    bytes: UnsafeRawPointer(pointer).advanced(by: location),
                    length: length,
                    encoding: String.Encoding.utf8.rawValue
                ) else {
                    continue
                }

                matches.add(substring)
                rangeValues.add(NSValue(range: NSRange(location: location, length: length)))
            }

            if let rangesPointer = ranges {
                rangesPointer.pointee = rangeValues
            }

            return matches
        }
    }

    @objc(grep:options:)
    func grep(_ pattern: String, options: Int32) -> Bool {
        substringsMatchingRegularExpression(
            pattern,
            count: -1,
            options: options,
            ranges: nil,
            error: nil
        ) != nil
    }

    private func assignRegexError(code: Int32,
                                  regex: UnsafePointer<regex_t>,
                                  errorPointer: NSErrorPointer) {
        guard let errorPointer else { return }

        var buffer = [CChar](repeating: 0, count: 256)
        let length = regerror(code, regex, &buffer, buffer.count)
        let description: String?
        if length > 0 {
            description = String(cString: buffer)
        } else {
            description = nil
        }

        var userInfo: [String: Any] = [:]
        if let description {
            userInfo[NSLocalizedDescriptionKey] = description
        }

        errorPointer.pointee = NSError(
            domain: regexErrorDomain,
            code: Int(code),
            userInfo: userInfo
        )
    }
}
