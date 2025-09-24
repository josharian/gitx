import Foundation

@objc(PBNSURLPathUserDefaultsTransfomer)
final class PBNSURLPathUserDefaultsTransfomer: ValueTransformer {
    override class func transformedValueClass() -> AnyClass {
        NSURL.self
    }

    override class func allowsReverseTransformation() -> Bool {
        true
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let pathString = value as? String, !pathString.isEmpty else {
            return nil
        }

        let baseURL = URL(string: "file://localhost/")
        guard let url = URL(string: pathString, relativeTo: baseURL) else {
            return nil
        }

        return url as NSURL
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let url = value as? NSURL else {
            return nil
        }

        return url.path
    }
}
