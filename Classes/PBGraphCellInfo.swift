import Foundation
import Darwin

@objcMembers
@objc(PBGraphCellInfo)
final class PBGraphCellInfo: NSObject {
    private var linesStorage: UnsafeMutablePointer<PBGitGraphLine>?

    @objc var position: Int
    @objc var numColumns: Int
    @objc var sign: Int8
    @objc var nLines: Int

    @objc(initWithPosition:andLines:)
    init(position: Int, andLines lines: UnsafeMutablePointer<PBGitGraphLine>?) {
        self.position = position
        self.numColumns = 0
        self.sign = 0
        self.nLines = 0
        self.linesStorage = lines
        super.init()
    }

    override init() {
        self.position = 0
        self.numColumns = 0
        self.sign = 0
        self.nLines = 0
        self.linesStorage = nil
        super.init()
    }

    deinit {
        freeLinesStorage()
    }

    var lines: UnsafeMutablePointer<PBGitGraphLine>? {
        get { linesStorage }
        set {
            if linesStorage != newValue {
                freeLinesStorage()
                linesStorage = newValue
            }
        }
    }

    private func freeLinesStorage() {
        if let pointer = linesStorage {
            free(pointer)
            linesStorage = nil
        }
    }
}
