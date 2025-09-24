//
//  PBGitRevisionCellView.h
//  GitX
//
//  View-based table cell for displaying git commits
//

#import <Cocoa/Cocoa.h>
#import "GitX-Swift.h"
#import "PBRefContextDelegate.h"

@class PBGitHistoryController;
@class PBGraphCellInfo;

@interface PBGitRevisionGraphView : NSView
@property (nonatomic, strong) PBGitCommit *commit;
@property (nonatomic, strong) PBGraphCellInfo *cellInfo;
@property (nonatomic, weak) id<PBRefContextDelegate> contextMenuDelegate;
@property (nonatomic, weak) PBGitHistoryController *controller;

- (int)indexAtX:(float)x;
- (NSRect)rectAtIndex:(int)index;
@end

@interface PBGitRevisionCellView : NSTableCellView
@property (nonatomic, strong) PBGitRevisionGraphView *graphView;
@property (nonatomic, strong) PBGitCommit *commit;

- (void)configureForCommit:(PBGitCommit *)commit withCellInfo:(PBGraphCellInfo *)cellInfo;
- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle;
@end
