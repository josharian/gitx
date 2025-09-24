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
