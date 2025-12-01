import Cocoa

@objc(PBSourceViewItem)
@objcMembers
open class PBSourceViewItem: NSObject {
    private var childrenSet = NSMutableOrderedSet()
    private var _title: String?
    private var _sortedChildren: [PBSourceViewItem]?

    @objc var revSpecifier: PBGitRevSpecifier?
    @objc var isGroupItem: Bool = false
    @objc var isUncollapsible: Bool = false
    @objc var isExpanded: Bool = false
    @objc weak var parent: PBSourceViewItem?

    @objc var title: String! {
        get {
            if let title = _title {
                return title
            }
            return (revSpecifier?.description as NSString?)?.lastPathComponent ?? ""
        }
        set {
            _title = newValue
        }
    }

    @objc var sortedChildren: [PBSourceViewItem] {
        if _sortedChildren == nil {
            let newArray = childrenSet.sortedArray { obj1, obj2 in
                let item1 = obj1 as! PBSourceViewItem
                let item2 = obj2 as! PBSourceViewItem
                return item1.title.localizedStandardCompare(item2.title)
            }
            _sortedChildren = newArray as? [PBSourceViewItem]
        }
        return _sortedChildren ?? []
    }

    @objc var iconName: String! {
        return ""
    }

    @objc var icon: NSImage! {
        return iconNamed(iconName)
    }

    public required override init() {
        super.init()
    }

    @objc(itemWithTitle:)
    static func item(withTitle title: String) -> Self {
        let item = self.init()
        item.title = title
        return item
    }

    @objc(groupItemWithTitle:)
    static func groupItem(withTitle title: String) -> Self {
        let item = self.item(withTitle: title.uppercased())
        item.isGroupItem = true
        return item
    }

    @objc(itemWithRevSpec:)
    static func item(withRevSpec revSpecifier: PBGitRevSpecifier) -> PBSourceViewItem {
        let ref = revSpecifier.ref

        if ref?.isTag == true {
            return PBGitSVTagItem.tagItem(with: revSpecifier)
        } else if ref?.isBranch == true {
            return PBGitSVBranchItem.branchItem(with: revSpecifier)
        } else if ref?.isRemoteBranch == true {
            return PBGitSVRemoteBranchItem.remoteBranchItem(with: revSpecifier)
        }

        return PBGitSVOtherRevItem.otherItem(with: revSpecifier)
    }

    @objc func addChild(_ child: PBSourceViewItem?) {
        guard let child = child else { return }

        childrenSet.add(child)
        _sortedChildren = nil
        child.parent = self
    }

    @objc func removeChild(_ child: PBSourceViewItem?) {
        guard let child = child else { return }

        childrenSet.remove(child)
        _sortedChildren = nil
        if !isGroupItem && childrenSet.count == 0 {
            parent?.removeChild(self)
        }
    }

    @objc func addRev(_ theRevSpecifier: PBGitRevSpecifier, toPath path: [String]) {
        if path.count == 1 {
            let item = PBSourceViewItem.item(withRevSpec: theRevSpecifier)
            addChild(item)
            return
        }

        let firstTitle = path[0]
        var node: PBSourceViewItem? = nil
        for child in childrenSet {
            if let item = child as? PBSourceViewItem, item.title == firstTitle {
                node = item
                break
            }
        }

        if node == nil {
            if firstTitle == theRevSpecifier.ref?.remoteName {
                node = PBGitSVRemoteItem.remoteItem(withTitle: firstTitle)
            } else {
                node = PBGitSVFolderItem.folderItem(withTitle: firstTitle)
                node?.isExpanded = (title == "BRANCHES")
            }
            addChild(node)
        }

        let subpath = Array(path.dropFirst())
        node?.addRev(theRevSpecifier, toPath: subpath)
    }

    @objc func findRev(_ rev: PBGitRevSpecifier) -> PBSourceViewItem? {
        if rev.isEqual(revSpecifier) {
            return self
        }

        for child in childrenSet {
            if let item = child as? PBSourceViewItem,
               let found = item.findRev(rev) {
                return found
            }
        }

        return nil
    }

    @objc func iconNamed(_ name: String) -> NSImage {
        guard let iconImage = NSImage(named: name) else {
            return NSImage()
        }
        iconImage.size = NSSize(width: 16, height: 16)
        iconImage.cacheMode = .always
        return iconImage
    }

    @objc var stringValue: String {
        return title
    }

    @objc func ref() -> PBGitRef? {
        if let revSpecifier = revSpecifier {
            return revSpecifier.ref
        }
        return nil
    }
}


@objc(PBSubmoduleInfo)
@objcMembers
final class PBSubmoduleInfo: NSObject {
    var name: String?
    var path: String?
    var parentRepositoryURL: URL?

    @objc(submodulesForRepositoryURL:)
    class func submodules(for repositoryURL: URL) -> [PBSubmoduleInfo] {
        let gitPath = PBGitBinary.path() ?? "/usr/bin/git"
        var exitCode: Int32 = 0
        guard let output = PBEasyPipe.outputForCommand(
            gitPath,
            withArgs: [
                "config",
                "--file",
                ".gitmodules",
                "--get-regexp",
                "^submodule\\..*\\.path$"
            ],
            inDir: repositoryURL.path,
            retValue: &exitCode
        ), exitCode == 0 else {
            return []
        }

        var submodules: [PBSubmoduleInfo] = []

        output.split(separator: "\n").forEach { rawLine in
            guard !rawLine.isEmpty else { return }
            let line = String(rawLine)

            guard let pathRange = line.range(of: "submodule."),
                  let dotPathRange = line.range(of: ".path "),
                  pathRange.upperBound <= dotPathRange.lowerBound else {
                return
            }

            let name = String(line[pathRange.upperBound..<dotPathRange.lowerBound])
            let pathComponent = String(line[dotPathRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !pathComponent.isEmpty else {
                return
            }

            let info = PBSubmoduleInfo()
            info.name = name
            info.path = pathComponent
            info.parentRepositoryURL = repositoryURL
            submodules.append(info)
        }

        return submodules
    }
}

@objc(PBGitSVSubmoduleItem)
@objcMembers
final class PBGitSVSubmoduleItem: PBSourceViewItem {
    var submodule: PBSubmoduleInfo?

    @objc(itemWithSubmodule:)
    class func item(with submodule: PBSubmoduleInfo) -> PBGitSVSubmoduleItem {
        let item = PBGitSVSubmoduleItem()
        item.submodule = submodule
        item.title = submodule.name
        return item
    }

    override var title: String! {
        get { submodule?.name }
        set { super.title = newValue }
    }

    var path: URL? {
        guard let parent = submodule?.parentRepositoryURL,
              let relative = submodule?.path else {
            return nil
        }

        return parent.appendingPathComponent(relative)
    }
}

@objc(PBGitSVRemoteItem)
@objcMembers
final class PBGitSVRemoteItem: PBSourceViewItem {
    @objc(remoteItemWithTitle:)
    class func remoteItem(withTitle title: String) -> PBGitSVRemoteItem {
        let item = PBGitSVRemoteItem()
        item.title = title
        return item
    }

    override var iconName: String! {
        "RemoteTemplate"
    }

    override func ref() -> PBGitRef? {
        guard let title = title else {
            return nil
        }
        return PBGitRef.refFromString("refs/remotes/" + title)
    }
}

@objc(PBGitSVBranchItem)
@objcMembers
final class PBGitSVBranchItem: PBSourceViewItem {
    @objc(branchItemWithRevSpec:)
    class func branchItem(with revSpecifier: PBGitRevSpecifier) -> PBGitSVBranchItem {
        let item = PBGitSVBranchItem()
        item.title = (revSpecifier.description as NSString).lastPathComponent
        item.revSpecifier = revSpecifier
        return item
    }

    override var iconName: String! {
        "BranchTemplate"
    }
}

@objc(PBGitSVRemoteBranchItem)
@objcMembers
final class PBGitSVRemoteBranchItem: PBSourceViewItem {
    @objc(remoteBranchItemWithRevSpec:)
    class func remoteBranchItem(with revSpecifier: PBGitRevSpecifier) -> PBGitSVRemoteBranchItem {
        let item = PBGitSVRemoteBranchItem()
        item.title = (revSpecifier.description as NSString).lastPathComponent
        item.revSpecifier = revSpecifier
        return item
    }

    override var iconName: String! {
        "RemoteBranchTemplate"
    }
}

@objc(PBGitSVStageItem)
@objcMembers
final class PBGitSVStageItem: PBSourceViewItem {
    @objc(stageItem)
    class func stageItem() -> PBGitSVStageItem {
        let item = PBGitSVStageItem()
        item.title = "Stage"
        return item
    }

    override var iconName: String! {
        "StageTemplate"
    }
}

@objc(PBGitSVTagItem)
@objcMembers
final class PBGitSVTagItem: PBSourceViewItem {
    @objc(tagItemWithRevSpec:)
    class func tagItem(with revSpecifier: PBGitRevSpecifier) -> PBGitSVTagItem {
        let item = PBGitSVTagItem()
        item.title = (revSpecifier.description as NSString).lastPathComponent
        item.revSpecifier = revSpecifier
        return item
    }

    override var iconName: String! {
        "TagTemplate"
    }
}

@objc(PBGitSVOtherRevItem)
@objcMembers
final class PBGitSVOtherRevItem: PBSourceViewItem {
    @objc(otherItemWithRevSpec:)
    class func otherItem(with revSpecifier: PBGitRevSpecifier) -> PBGitSVOtherRevItem {
        let item = PBGitSVOtherRevItem()
        item.title = revSpecifier.title
        item.revSpecifier = revSpecifier
        return item
    }

    override var iconName: String! {
        "BranchTemplate"
    }
}

@objc(PBGitSVFolderItem)
@objcMembers
final class PBGitSVFolderItem: PBSourceViewItem {
    @objc(folderItemWithTitle:)
    class func folderItem(withTitle title: String) -> PBGitSVFolderItem {
        let item = PBGitSVFolderItem()
        item.title = title
        return item
    }

    override var iconName: String! {
        isExpanded ? "FolderTemplate" : "FolderClosedTemplate"
    }
}

@objc(PBSourceViewRemote)
@objcMembers
final class PBSourceViewRemote: PBSourceViewItem {
    override var icon: NSImage! {
        return NSImage(named: "remote")
    }
}

@objc(PBSourceViewAction)
@objcMembers
final class PBSourceViewAction: PBSourceViewItem {
    private var _actionIcon: NSImage?

    @objc override var icon: NSImage! {
        get { _actionIcon }
        set { _actionIcon = newValue }
    }
}
