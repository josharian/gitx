//
//  PBCommitListRowView.h
//  GitX
//
//  Custom row view for commit list that handles search highlighting
//

#import <Cocoa/Cocoa.h>

@interface PBCommitListRowView : NSTableRowView

@property (nonatomic, assign) BOOL isSearchResult;
@property (nonatomic, assign) BOOL isCurrentSearchResult;

@end