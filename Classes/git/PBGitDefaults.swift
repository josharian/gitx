import Foundation

@objcMembers
@objc(PBGitDefaults)
final class PBGitDefaults: NSObject {
    private enum Key {
        static let commitMessageViewVerticalLineLength = "PBCommitMessageViewVerticalLineLength"
        static let commitMessageViewVerticalBodyLineLength = "PBCommitMessageViewVerticalBodyLineLength"
        static let commitMessageViewHasVerticalLine = "PBCommitMessageViewHasVerticalLine"
        static let showWhitespaceDifferences = "PBShowWhitespaceDifferences"
        static let shouldCheckoutBranch = "PBShouldCheckoutBranch"
        static let showStageView = "PBShowStageView"
        static let branchFilterState = "PBBranchFilter"
        static let historySearchMode = "PBHistorySearchMode"
        static let suppressedDialogWarnings = "Suppressed Dialog Warnings"
    }

    private static let defaults = UserDefaults.standard

    private static let registeredDefaults: Void = {
        defaults.register(defaults: [
            Key.commitMessageViewVerticalLineLength: 50,
            Key.commitMessageViewVerticalBodyLineLength: 72,
            Key.commitMessageViewHasVerticalLine: true,
            Key.showWhitespaceDifferences: true,
            Key.shouldCheckoutBranch: true,
            Key.showStageView: true,
            Key.historySearchMode: 1,
            Key.branchFilterState: 0
        ])
    }()

    private class func ensureDefaultsRegistered() {
        _ = registeredDefaults
    }

    @objc class func commitMessageViewVerticalLineLength() -> Int {
        ensureDefaultsRegistered()
        return defaults.integer(forKey: Key.commitMessageViewVerticalLineLength)
    }

    @objc class func commitMessageViewVerticalBodyLineLength() -> Int {
        ensureDefaultsRegistered()
        return defaults.integer(forKey: Key.commitMessageViewVerticalBodyLineLength)
    }

    @objc class func commitMessageViewHasVerticalLine() -> Bool {
        ensureDefaultsRegistered()
        return defaults.bool(forKey: Key.commitMessageViewHasVerticalLine)
    }

    @objc class func showWhitespaceDifferences() -> Bool {
        ensureDefaultsRegistered()
        return defaults.bool(forKey: Key.showWhitespaceDifferences)
    }

    @objc class func shouldCheckoutBranch() -> Bool {
        ensureDefaultsRegistered()
        return defaults.bool(forKey: Key.shouldCheckoutBranch)
    }

    @objc class func setShouldCheckoutBranch(_ shouldCheckout: Bool) {
        ensureDefaultsRegistered()
        defaults.set(shouldCheckout, forKey: Key.shouldCheckoutBranch)
    }

    @objc class func showStageView() -> Bool {
        ensureDefaultsRegistered()
        return defaults.bool(forKey: Key.showStageView)
    }

    @objc class func setShowStageView(_ suppress: Bool) {
        ensureDefaultsRegistered()
        defaults.set(suppress, forKey: Key.showStageView)
    }

    @objc class func branchFilter() -> NSInteger {
        ensureDefaultsRegistered()
        return defaults.integer(forKey: Key.branchFilterState)
    }

    @objc class func setBranchFilter(_ state: NSInteger) {
        ensureDefaultsRegistered()
        defaults.set(state, forKey: Key.branchFilterState)
    }

    @objc class func historySearchMode() -> NSInteger {
        ensureDefaultsRegistered()
        return defaults.integer(forKey: Key.historySearchMode)
    }

    @objc class func setHistorySearchMode(_ mode: NSInteger) {
        ensureDefaultsRegistered()
        defaults.set(mode, forKey: Key.historySearchMode)
    }

    @objc class func suppressDialogWarningForDialog(_ dialog: String) {
        ensureDefaultsRegistered()
        var suppressed = Set(defaults.stringArray(forKey: Key.suppressedDialogWarnings) ?? [])
        suppressed.insert(dialog)
        defaults.set(Array(suppressed), forKey: Key.suppressedDialogWarnings)
    }

    @objc class func isDialogWarningSuppressedForDialog(_ dialog: String) -> Bool {
        ensureDefaultsRegistered()
        let suppressed = Set(defaults.stringArray(forKey: Key.suppressedDialogWarnings) ?? [])
        return suppressed.contains(dialog)
    }

    @objc class func resetAllDialogWarnings() {
        ensureDefaultsRegistered()
        defaults.removeObject(forKey: Key.suppressedDialogWarnings)
        defaults.synchronize()
    }
}
