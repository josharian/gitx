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
	// Restore split view position synchronously after view is properly set up
	[self restoreSplitViewPosition];

	[upperToolbarView setTopShade:237.0f/255.0f bottomShade:216.0f/255.0f];
	
	// Always use All branches filter
	repository.currentBranchFilter = kGitXAllBranchesFilter;


	__unsafe_unretained PBGitHistoryController *weakSelf = self;
	commitList.findPanelActionBlock = ^(id sender) {
		[weakSelf.view.window makeFirstResponder:weakSelf->searchField];
	};

	[super awakeFromNib];
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
	if ([firstResponder isKindOfClass:[NSTextView class]]) {
		[(NSTextView *)firstResponder performFindPanelAction:sender];
		return;
	}

	[searchController selectNextResult];
}
- (IBAction)selectPrevious:(id)sender
{
	NSResponder *firstResponder = [[[self view] window] firstResponder];
	if ([firstResponder isKindOfClass:[NSTextView class]]) {
		[(NSTextView *)firstResponder performFindPanelAction:sender];
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

	NSInteger newIndex = (NSInteger)[[commitController selectionIndexes] firstIndex];

	if (newIndex > oldIndex) {
        CGFloat sviewHeight = [[commitList superview] bounds].size.height;
        CGFloat rowHeight = [commitList rowHeight];
		NSInteger visibleRows = (NSInteger)roundf((float)(sviewHeight / rowHeight));
		newIndex += (visibleRows - 1);
		if (newIndex >= (NSInteger)[[commitController content] count])
			newIndex = (NSInteger)[[commitController content] count] - 1;
	}

    if (newIndex != oldIndex) {
        commitList.useAdjustScroll = YES;
    }

	[commitList scrollRowToVisible:newIndex];
    commitList.useAdjustScroll = NO;
}

- (NSArray *) selectedObjectsForSHA:(NSString *)commitSHA
{
	NSPredicate *selection = [NSPredicate predicateWithFormat:@"sha == %@", commitSHA];
	NSArray *selectedCommits = [[commitController content] filteredArrayUsingPredicate:selection];

	if (([selectedCommits count] == 0) && [self firstCommit])
		selectedCommits = [NSArray arrayWithObject:[self firstCommit]];

	return selectedCommits;
}

- (void)selectCommit:(NSString *)commitSHA
{
	if (!forceSelectionUpdate && [[[[commitController selectedObjects] lastObject] sha] isEqual:commitSHA])
		return;

	NSInteger oldIndex = (NSInteger)[[commitController selectionIndexes] firstIndex];

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

	float dividerThickness = (float)[splitView dividerThickness];

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
	float position = (float)[[[historySplitView subviews] objectAtIndex:0] frame].size.height;
	[[NSUserDefaults standardUserDefaults] setFloat:position forKey:kHistorySplitViewPositionDefault];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

// make sure this happens after awakeFromNib
- (void)restoreSplitViewPosition
{
	float position = [[NSUserDefaults standardUserDefaults] floatForKey:kHistorySplitViewPositionDefault];
	if (position < 1.0) {
		// Default to 40% of the split view height for the top (history) view
		float splitViewHeight = [historySplitView frame].size.height;
		position = splitViewHeight * 0.4f;
		// Ensure position respects minimum constraints
		if (position < historySplitView.topViewMin)
			position = historySplitView.topViewMin;
		else if (position > (splitViewHeight - historySplitView.bottomViewMin - [historySplitView dividerThickness]))
			position = splitViewHeight - historySplitView.bottomViewMin - [historySplitView dividerThickness];
	}

	[historySplitView setPosition:position ofDividerAtIndex:0];
	
	// Force the split view to recalculate and adjust subview layouts
	[historySplitView adjustSubviews];
	
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




@end
