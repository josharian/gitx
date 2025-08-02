//
//  PBGitHistoryView.h
//  GitX
//
//  Created by Pieter de Bie on 19-09-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PBViewController.h"

@class PBGitCommit;
@class PBGitTree;
@class PBCollapsibleSplitView;

@class PBGitSidebarController;
@class PBWebHistoryController;
@class PBGitGradientBarView;
@class PBRefController;
@class QLPreviewPanel;
@class PBCommitList;
@class GTOID;
@class PBHistorySearchController;

@interface PBGitHistoryController : PBViewController {
	IBOutlet PBRefController *refController;
	IBOutlet NSSearchField *searchField;
	IBOutlet NSArrayController* commitController;
	IBOutlet PBCommitList* commitList;
	IBOutlet PBCollapsibleSplitView *historySplitView;
	IBOutlet PBWebHistoryController *webHistoryController;
    QLPreviewPanel* previewPanel;
	IBOutlet PBHistorySearchController *searchController;

	IBOutlet PBGitGradientBarView *upperToolbarView;
	IBOutlet NSButton *mergeButton;
	IBOutlet NSButton *cherryPickButton;
	IBOutlet NSButton *rebaseButton;


	IBOutlet id webView;
	BOOL forceSelectionUpdate;
	
	PBGitCommit *webCommit;
	PBGitCommit *selectedCommit;
}

@property  PBGitCommit *webCommit;
@property (readonly) NSArrayController *commitController;
@property (readonly) PBRefController *refController;
@property (readonly) PBHistorySearchController *searchController;
@property (readonly) PBCommitList *commitList;

- (void)selectCommit:(GTOID *)commit;
- (IBAction) refresh:(id)sender;
- (IBAction) toggleQLPreviewPanel:(id)sender;
- (void) updateQuicklookForce: (BOOL) force;

// Repository Methods
- (IBAction) createBranch:(id)sender;
- (IBAction) createTag:(id)sender;
- (IBAction) merge:(id)sender;
- (IBAction) cherryPick:(id)sender;
- (IBAction) rebase:(id)sender;

// Find/Search methods
- (IBAction)selectNext:(id)sender;
- (IBAction)selectPrevious:(id)sender;

- (void) copyCommitInfo;
- (void) copyCommitSHA;

- (BOOL) hasNonlinearPath;

- (NSMenu *)tableColumnMenu;

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview;
- (BOOL)splitView:(NSSplitView *)splitView shouldCollapseSubview:(NSView *)subview forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex;
- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset;
- (CGFloat)splitView:(NSSplitView *)sender constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)offset;

@end
