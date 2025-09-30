import Cocoa

@objc class PBRefMenuItem: NSMenuItem {
    @objc var refish: PBGitRefish?

    @objc(itemWithTitle:action:enabled:)
    static func item(withTitle title: String, action selector: Selector?, enabled isEnabled: Bool) -> PBRefMenuItem {
        let actualSelector = isEnabled ? selector : nil
        let item = PBRefMenuItem(title: title, action: actualSelector, keyEquivalent: "")
        item.isEnabled = isEnabled
        return item
    }

    @objc override static func separator() -> Self {
        return unsafeDowncast(super.separator(), to: Self.self)
    }

    @objc(defaultMenuItemsForRef:inRepository:target:)
    static func defaultMenuItems(for ref: PBGitRef?, in repo: PBGitRepository?, target: Any?) -> [PBRefMenuItem]? {
        guard let ref = ref, let repo = repo, let target = target else {
            return nil
        }

        var items: [PBRefMenuItem] = []

        let targetRefName = ref.shortName()

        let headRef = repo.headRef()?.ref()
        let headRefName = headRef?.shortName() ?? ""
        let isHead = ref.isEqual(to: headRef)
        let isOnHeadBranch = isHead ? true : repo.isRef(onHeadBranch: ref)
        let isDetachedHead = (isHead && headRefName == "HEAD")

        let isRemote = (ref.isRemote && !ref.isRemoteBranch)

        if !isRemote {
            // checkout ref
            let checkoutTitle = "Checkout " + targetRefName
            items.append(.item(withTitle: checkoutTitle, action: #selector(checkout(_:)), enabled: !isHead))
            items.append(.separator())

            // create branch
            let createBranchTitle = ref.isRemoteBranch
                ? "Create branch that tracks \(targetRefName)…"
                : "Create branch…"
            items.append(.item(withTitle: createBranchTitle, action: #selector(createBranch(_:)), enabled: true))

            // create tag
            items.append(.item(withTitle: "Create Tag…", action: #selector(createTag(_:)), enabled: true))

            // view tag info
            if ref.isTag {
                items.append(.item(withTitle: "View tag info…", action: #selector(showTagInfoSheet(_:)), enabled: true))
            }

            items.append(.separator())

            // merge ref
            let mergeTitle = isOnHeadBranch
                ? "Merge"
                : "Merge \(targetRefName) into \(headRefName)"
            items.append(.item(withTitle: mergeTitle, action: #selector(merge(_:)), enabled: !isOnHeadBranch))

            // rebase
            let rebaseTitle = isOnHeadBranch
                ? "Rebase"
                : "Rebase \(headRefName) on \(targetRefName)"
            items.append(.item(withTitle: rebaseTitle, action: #selector(rebaseHeadBranch(_:)), enabled: !isOnHeadBranch))

            items.append(.separator())
        }

        // delete ref
        items.append(.separator())
        do {
            // Don't show delete/remove options for remotes since we don't support remote operations
            if !ref.isRemote {
                let deleteTitle = "Delete \(targetRefName)…"
                let deleteEnabled = !(isDetachedHead || isHead)
                let deleteItem = PBRefMenuItem.item(withTitle: deleteTitle, action: #selector(showDeleteRefSheet(_:)), enabled: deleteEnabled)
                items.append(deleteItem)
            }
        }

        for item in items {
            item.target = target as AnyObject?
            item.refish = ref
        }

        return items
    }

    @objc(defaultMenuItemsForCommit:target:)
    static func defaultMenuItems(for commit: PBGitCommit?, target: Any?) -> [PBRefMenuItem]? {
        guard let commit = commit else {
            return nil
        }

        var items: [PBRefMenuItem] = []

        let headBranchName = commit.repository?.headRef()?.ref().shortName() ?? ""
        let isOnHeadBranch = commit.isOnHeadBranch()

        items.append(.item(withTitle: "Checkout Commit", action: #selector(checkout(_:)), enabled: true))
        items.append(.separator())

        items.append(.item(withTitle: "Create Branch…", action: #selector(createBranch(_:)), enabled: true))
        items.append(.item(withTitle: "Create Tag…", action: #selector(createTag(_:)), enabled: true))
        items.append(.separator())

        items.append(.item(withTitle: "Copy SHA", action: #selector(copySHA(_:)), enabled: true))
        items.append(.item(withTitle: "Copy short SHA", action: #selector(copyShortSHA(_:)), enabled: true))
        items.append(.item(withTitle: "Copy Patch", action: #selector(copyPatch(_:)), enabled: true))
        items.append(.separator())

        // merge commit
        let mergeTitle = isOnHeadBranch
            ? "Merge commit"
            : "Merge commit into \(headBranchName)"
        items.append(.item(withTitle: mergeTitle, action: #selector(merge(_:)), enabled: !isOnHeadBranch))

        // cherry pick
        let cherryPickTitle = isOnHeadBranch
            ? "Cherry pick commit"
            : "Cherry pick commit to \(headBranchName)"
        items.append(.item(withTitle: cherryPickTitle, action: #selector(cherryPick(_:)), enabled: !isOnHeadBranch))

        // rebase
        let rebaseTitle = isOnHeadBranch
            ? "Rebase commit"
            : "Rebase \(headBranchName) on commit"
        items.append(.item(withTitle: rebaseTitle, action: #selector(rebaseHeadBranch(_:)), enabled: !isOnHeadBranch))

        for item in items {
            item.target = target as AnyObject?
            item.refish = commit
        }

        return items
    }

    // MARK: - Dummy selector declarations for the compiler
    // These are actually implemented by the target objects

    @objc private func checkout(_ sender: Any?) {}
    @objc private func createBranch(_ sender: Any?) {}
    @objc private func createTag(_ sender: Any?) {}
    @objc private func showTagInfoSheet(_ sender: Any?) {}
    @objc private func merge(_ sender: Any?) {}
    @objc private func rebaseHeadBranch(_ sender: Any?) {}
    @objc private func showDeleteRefSheet(_ sender: Any?) {}
    @objc private func copySHA(_ sender: Any?) {}
    @objc private func copyShortSHA(_ sender: Any?) {}
    @objc private func copyPatch(_ sender: Any?) {}
    @objc private func cherryPick(_ sender: Any?) {}
}