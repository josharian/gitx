//
//  PBGitHistoryView.m
//  GitX
//
//  Created by Pieter de Bie on 19-09-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitCommit.h"
#import "PBGitTree.h"
#import "PBGitRef.h"
#import "PBGitHistoryList.h"
#import "PBGitRevSpecifier.h"
#import "PBCollapsibleSplitView.h"
#import "PBGitHistoryController.h"
#import "PBWebHistoryController.h"
#import "CWQuickLook.h"
#import "PBGitGrapher.h"
#import "PBGitRevisionCell.h"
#import "PBCommitList.h"
#import "PBCreateBranchSheet.h"
#import "PBCreateTagSheet.h"
#import "PBGitSidebarController.h"
#import "PBGitGradientBarView.h"
#import "PBDiffWindowController.h"
#import "PBGitDefaults.h"
#import "PBGitRevList.h"
#import "PBHistorySearchController.h"
#import "PBGitRepositoryWatcher.h"
#define QLPreviewPanel NSClassFromString(@"QLPreviewPanel")
#import "PBQLTextView.h"
#import "GLFileView.h"

#define kHistorySplitViewPositionDefault @"History SplitView Position"

@interface PBGitHistoryController ()

- (void)saveSplitViewPosition;

@end


@implementation PBGitHistoryController
@synthesize webCommit, commitController, refController;
@synthesize searchController;
@synthesize commitList;

- (void)awakeFromNib
{
	[commitController addObserver:self forKeyPath:@"selection" options:0 context:@"commitChange"];
	[commitController addObserver:self forKeyPath:@"arrangedObjects.@count" options:NSKeyValueObservingOptionInitial context:@"updateCommitCount"];

	[repository.revisionList addObserver:self forKeyPath:@"isUpdating" options:0 context:@"revisionListUpdating"];
	[repository addObserver:self forKeyPath:@"currentBranch" options:0 context:@"branchChange"];
	[repository addObserver:self forKeyPath:@"refs" options:0 context:@"updateRefs"];

	forceSelectionUpdate = YES;
	NSSize cellSpacing = [commitList intercellSpacing];
	cellSpacing.height = 0;
	[commitList setIntercellSpacing:cellSpacing];

	if (!repository.currentBranch) {
		[repository reloadRefs];
		[repository readCurrentBranch];
	}
	else
		[repository lazyReload];


	// Set a sort descriptor for the subject column in the history list, as
	// It can't be sorted by default (because it's bound to a PBGitCommit)
	[[commitList tableColumnWithIdentifier:@"SubjectColumn"] setSortDescriptorPrototype:[[NSSortDescriptor alloc] initWithKey:@"subject" ascending:YES]];
	// Add a menu that allows a user to select which columns to view
	[[commitList headerView] setMenu:[self tableColumnMenu]];

	[historySplitView setTopMin:58.0 andBottomMin:100.0];
	[historySplitView setHidden:YES];
	[self performSelector:@selector(restoreSplitViewPositiion) withObject:nil afterDelay:0];

	[upperToolbarView setTopShade:237/255.0 bottomShade:216/255.0];
	
	// Always use All branches filter
	repository.currentBranchFilter = kGitXAllBranchesFilter;

	// listen for updates
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_repositoryUpdatedNotification:) name:PBGitRepositoryEventNotification object:repository];

	__unsafe_unretained PBGitHistoryController *weakSelf = self;
	commitList.findPanelActionBlock = ^(id sender) {
		[weakSelf.view.window makeFirstResponder:weakSelf->searchField];
	};

	[super awakeFromNib];
}

- (void) _repositoryUpdatedNotification:(NSNotification *)notification {
    PBGitRepositoryWatcherEventType eventType = [(NSNumber *)[[notification userInfo] objectForKey:kPBGitRepositoryEventTypeUserInfoKey] unsignedIntValue];
    if(eventType & PBGitRepositoryWatcherEventTypeGitDirectory){
      // refresh if the .git repository is modified
      [self refresh:NULL];
    }
}

- (void)updateKeys
{
	PBGitCommit *lastObject = [[commitController selectedObjects] lastObject];
	if (lastObject) {
		if (![selectedCommit isEqual:lastObject]) {
			selectedCommit = lastObject;

			BOOL isOnHeadBranch = [selectedCommit isOnHeadBranch];
			[mergeButton setEnabled:!isOnHeadBranch];
			[cherryPickButton setEnabled:!isOnHeadBranch];
			[rebaseButton setEnabled:!isOnHeadBranch];
		}
	}
	else {
		[mergeButton setEnabled:NO];
		[cherryPickButton setEnabled:NO];
		[rebaseButton setEnabled:NO];
	}

	if (![self.webCommit isEqual:selectedCommit])
		self.webCommit = selectedCommit;
}


- (PBGitCommit *) firstCommit
{
	NSArray *arrangedObjects = [commitController arrangedObjects];
	if ([arrangedObjects count] > 0)
		return [arrangedObjects objectAtIndex:0];

	return nil;
}

- (BOOL)isCommitSelected
{
	return [selectedCommit isEqual:[[commitController selectedObjects] lastObject]];
}


- (void) updateStatus
{
	self.isBusy = repository.revisionList.isUpdating;
	self.status = [NSString stringWithFormat:@"%lu commits loaded", [[commitController arrangedObjects] count]];
}


- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	NSString* strContext = (__bridge NSString*)context;
    if ([strContext isEqualToString: @"commitChange"]) {
		[self updateKeys];
		return;
	}

	if([strContext isEqualToString:@"branchChange"]) {
		// Reset the sorting
		if ([[commitController sortDescriptors] count])
			[commitController setSortDescriptors:[NSArray array]];
		return;
	}

	if([strContext isEqualToString:@"updateRefs"]) {
		[commitController rearrangeObjects];
		return;
	}

	if([strContext isEqualToString:@"updateCommitCount"] || [(__bridge NSString *)context isEqualToString:@"revisionListUpdating"]) {
		[self updateStatus];

		if ([repository.currentBranch isSimpleRef])
			[self selectCommit:[repository shaForRef:[repository.currentBranch ref]]];
		else
			[self selectCommit:[[self firstCommit] sha]];
		return;
	}

	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}



- (void)keyDown:(NSEvent*)event
{
	if ([[event charactersIgnoringModifiers] isEqualToString: @"f"] && [event modifierFlags] & NSEventModifierFlagOption && [event modifierFlags] & NSEventModifierFlagCommand)
		[superController.window makeFirstResponder: searchField];
	else
		[super keyDown: event];
}

// NSSearchField (actually textfields in general) prevent the normal Find operations from working. Setup custom actions for the
// next and previous menuitems (in MainMenu.nib) so they will work when the search field is active. When searching for text in
// a file make sure to call the Find panel's action method instead.
- (IBAction)selectNext:(id)sender
{
	NSResponder *firstResponder = [[[self view] window] firstResponder];
	if ([firstResponder isKindOfClass:[PBQLTextView class]]) {
		[(PBQLTextView *)firstResponder performFindPanelAction:sender];
		return;
	}

	[searchController selectNextResult];
}
- (IBAction)selectPrevious:(id)sender
{
	NSResponder *firstResponder = [[[self view] window] firstResponder];
	if ([firstResponder isKindOfClass:[PBQLTextView class]]) {
		[(PBQLTextView *)firstResponder performFindPanelAction:sender];
		return;
	}

	[searchController selectPreviousResult];
}

- (void) copyCommitInfo
{
	PBGitCommit *commit = [[commitController selectedObjects] objectAtIndex:0];
	if (!commit)
		return;
	NSString *info = [NSString stringWithFormat:@"%@ (%@)", [[commit realSha] substringToIndex:10], [commit subject]];

	NSPasteboard *a =[NSPasteboard generalPasteboard];
	[a declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:self];
	[a setString:info forType: NSStringPboardType];
	
}

- (void) copyCommitSHA
{
	PBGitCommit *commit = [[commitController selectedObjects] objectAtIndex:0];
	if (!commit)
		return;
	NSString *info = [[commit realSha] substringWithRange:NSMakeRange(0, 7)];

	NSPasteboard *a =[NSPasteboard generalPasteboard];
	[a declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:self];
	[a setString:info forType: NSStringPboardType];

}

- (IBAction) toggleQLPreviewPanel:(id)sender
{
	if ([[QLPreviewPanel sharedPreviewPanel] respondsToSelector:@selector(setDataSource:)]) {
		// Public QL API
		if ([QLPreviewPanel sharedPreviewPanelExists] && [[QLPreviewPanel sharedPreviewPanel] isVisible])
			[[QLPreviewPanel sharedPreviewPanel] orderOut:nil];
		else
			[[QLPreviewPanel sharedPreviewPanel] makeKeyAndOrderFront:nil];
	}
	else {
		// Private QL API (10.5 only)
		if ([[QLPreviewPanel sharedPreviewPanel] isOpen])
			[[QLPreviewPanel sharedPreviewPanel] closePanel];
		else {
			[[QLPreviewPanel sharedPreviewPanel] makeKeyAndOrderFrontWithEffect:1];
			[self updateQuicklookForce:YES];
		}
	}
}

- (void) updateQuicklookForce:(BOOL)force
{
	if (!force && ![[QLPreviewPanel sharedPreviewPanel] isOpen])
		return;

	if ([[QLPreviewPanel sharedPreviewPanel] respondsToSelector:@selector(setDataSource:)]) {
		// Public QL API
		[previewPanel reloadData];
	}
}

- (IBAction) refresh:(id)sender
{
	[repository forceUpdateRevisions];
}

- (void) updateView
{
	[self updateKeys];
}

- (NSResponder *)firstResponder;
{
	return commitList;
}

- (void) scrollSelectionToTopOfViewFrom:(NSInteger)oldIndex
{
	if (oldIndex == NSNotFound)
		oldIndex = 0;

	NSInteger newIndex = [[commitController selectionIndexes] firstIndex];

	if (newIndex > oldIndex) {
        CGFloat sviewHeight = [[commitList superview] bounds].size.height;
        CGFloat rowHeight = [commitList rowHeight];
		NSInteger visibleRows = roundf(sviewHeight / rowHeight );
		newIndex += (visibleRows - 1);
		if (newIndex >= [[commitController content] count])
			newIndex = [[commitController content] count] - 1;
	}

    if (newIndex != oldIndex) {
        commitList.useAdjustScroll = YES;
    }

	[commitList scrollRowToVisible:newIndex];
    commitList.useAdjustScroll = NO;
}

- (NSArray *) selectedObjectsForSHA:(GTOID *)commitSHA
{
	NSPredicate *selection = [NSPredicate predicateWithFormat:@"sha == %@", commitSHA];
	NSArray *selectedCommits = [[commitController content] filteredArrayUsingPredicate:selection];

	if (([selectedCommits count] == 0) && [self firstCommit])
		selectedCommits = [NSArray arrayWithObject:[self firstCommit]];

	return selectedCommits;
}

- (void)selectCommit:(GTOID *)commitSHA
{
	if (!forceSelectionUpdate && [[[[commitController selectedObjects] lastObject] sha] isEqual:commitSHA])
		return;

	NSInteger oldIndex = [[commitController selectionIndexes] firstIndex];

	NSArray *selectedCommits = [self selectedObjectsForSHA:commitSHA];
	[commitController setSelectedObjects:selectedCommits];

	[self scrollSelectionToTopOfViewFrom:oldIndex];

	forceSelectionUpdate = NO;
}

- (BOOL) hasNonlinearPath
{
	return [commitController filterPredicate] || [[commitController sortDescriptors] count] > 0;
}

- (void)closeView
{
	[self saveSplitViewPosition];

	if (commitController) {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
		[commitController removeObserver:self forKeyPath:@"selection"];
		[commitController removeObserver:self forKeyPath:@"arrangedObjects.@count"];

		[repository.revisionList removeObserver:self forKeyPath:@"isUpdating"];
		[repository removeObserver:self forKeyPath:@"currentBranch"];
		[repository removeObserver:self forKeyPath:@"refs"];
	}

	[webHistoryController closeView];
	[fileView closeView];

	[super closeView];
}

#pragma mark Table Column Methods
- (NSMenu *)tableColumnMenu
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Table columns menu"];
	for (NSTableColumn *column in [commitList tableColumns]) {
		NSMenuItem *item = [[NSMenuItem alloc] init];
		[item setTitle:[[column headerCell] stringValue]];
		[item bind:@"value"
		  toObject:column
	   withKeyPath:@"hidden"
		   options:[NSDictionary dictionaryWithObject:@"NSNegateBoolean" forKey:NSValueTransformerNameBindingOption]];
		[menu addItem:item];
	}
	return menu;
}




#pragma mark NSSplitView delegate methods

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview
{
	return TRUE;
}

- (BOOL)splitView:(NSSplitView *)splitView shouldCollapseSubview:(NSView *)subview forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex
{
	NSUInteger index = [[splitView subviews] indexOfObject:subview];
	// this method (and canCollapse) are called by the splitView to decide how to collapse on double-click
	// we compare our two subviews, so that always the smaller one is collapsed.
	if([[[splitView subviews] objectAtIndex:index] frame].size.height < [[[splitView subviews] objectAtIndex:((index+1)%2)] frame].size.height) {
		return TRUE;
	}
	return FALSE;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex
{
	return historySplitView.topViewMin;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex
{
	return [splitView frame].size.height - [splitView dividerThickness] - historySplitView.bottomViewMin;
}

// while the user resizes the window keep the upper (history) view constant and just resize the lower view
// unless the lower view gets too small
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize
{
	NSRect newFrame = [splitView frame];

	float dividerThickness = [splitView dividerThickness];

	NSView *upperView = [[splitView subviews] objectAtIndex:0];
	NSRect upperFrame = [upperView frame];
	upperFrame.size.width = newFrame.size.width;

	if ((newFrame.size.height - upperFrame.size.height - dividerThickness) < historySplitView.bottomViewMin) {
		upperFrame.size.height = newFrame.size.height - historySplitView.bottomViewMin - dividerThickness;
	}

	NSView *lowerView = [[splitView subviews] objectAtIndex:1];
	NSRect lowerFrame = [lowerView frame];
	lowerFrame.origin.y = upperFrame.size.height + dividerThickness;
	lowerFrame.size.height = newFrame.size.height - lowerFrame.origin.y;
	lowerFrame.size.width = newFrame.size.width;

	[upperView setFrame:upperFrame];
	[lowerView setFrame:lowerFrame];
}

// NSSplitView does not save and restore the position of the SplitView correctly so do it manually
- (void)saveSplitViewPosition
{
	float position = [[[historySplitView subviews] objectAtIndex:0] frame].size.height;
	[[NSUserDefaults standardUserDefaults] setFloat:position forKey:kHistorySplitViewPositionDefault];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

// make sure this happens after awakeFromNib
- (void)restoreSplitViewPositiion
{
	float position = [[NSUserDefaults standardUserDefaults] floatForKey:kHistorySplitViewPositionDefault];
	if (position < 1.0)
		position = 175;

	[historySplitView setPosition:position ofDividerAtIndex:0];
	[historySplitView setHidden:NO];
}


#pragma mark Repository Methods

- (IBAction) createBranch:(id)sender
{
	PBGitRef *currentRef = [repository.currentBranch ref];

	if (!selectedCommit || [selectedCommit hasRef:currentRef])
		[PBCreateBranchSheet beginCreateBranchSheetAtRefish:currentRef inRepository:self.repository];
	else
		[PBCreateBranchSheet beginCreateBranchSheetAtRefish:selectedCommit inRepository:self.repository];
}

- (IBAction) createTag:(id)sender
{
	if (!selectedCommit)
		[PBCreateTagSheet beginCreateTagSheetAtRefish:[repository.currentBranch ref] inRepository:repository];
	else
		[PBCreateTagSheet beginCreateTagSheetAtRefish:selectedCommit inRepository:repository];
}


- (IBAction) merge:(id)sender
{
	if (selectedCommit)
		[repository mergeWithRefish:selectedCommit];
}

- (IBAction) cherryPick:(id)sender
{
	if (selectedCommit)
		[repository cherryPickRefish:selectedCommit];
}

- (IBAction) rebase:(id)sender
{
	if (selectedCommit)
		[repository rebaseBranch:nil onRefish:selectedCommit];
}

#pragma mark -
#pragma mark Quick Look Public API support

@protocol QLPreviewItem;

#pragma mark (QLPreviewPanelController)

- (BOOL) acceptsPreviewPanelControl:(id)panel
{
    return YES;
}

- (void)beginPreviewPanelControl:(id)panel
{
    // This document is now responsible of the preview panel
    // It is allowed to set the delegate, data source and refresh panel.
    previewPanel = panel;
	[previewPanel setDelegate:self];
	[previewPanel setDataSource:self];
}

- (void)endPreviewPanelControl:(id)panel
{
    // This document loses its responsisibility on the preview panel
    // Until the next call to -beginPreviewPanelControl: it must not
    // change the panel's delegate, data source or refresh it.
    previewPanel = nil;
}



@end
