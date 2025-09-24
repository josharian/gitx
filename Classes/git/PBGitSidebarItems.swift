import Foundation

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
        item.title = revSpecifier.title()
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
