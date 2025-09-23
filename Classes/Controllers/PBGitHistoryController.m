//
//  PBGitHistoryView.m
//  GitX
//
//  Created by Pieter de Bie on 19-09-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "GitX-Swift.h"
#import "PBGitRef.h"
#import "PBGitHistoryList.h"
#import "PBGitRevSpecifier.h"
#import "PBCollapsibleSplitView.h"
#import "PBGitHistoryController.h"
#import "PBWebHistoryController.h"
#import "PBGitGrapher.h"
#import "PBGitRevisionCell.h"
#import "PBGitRevisionCellView.h"
#import "PBGitTableCellView.h"
#import "PBCommitList.h"
#import "PBCommitListRowView.h"
#import "PBRefController.h"
#import "PBCreateBranchSheet.h"
#import "PBCreateTagSheet.h"
#import "PBGitSidebarController.h"
#import "PBGitGradientBarView.h"
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
	
	// Remove bindings from columns to force view-based approach
	for (NSTableColumn *column in [commitList tableColumns]) {
		[column unbind:NSValueBinding];
		[[column dataCell] unbind:NSValueBinding];
	}
	
	// Set up for view-based table view
	[commitList setDelegate:self];
	[commitList setDataSource:self];
	[commitList reloadData];

	if (!repository.currentBranch) {
		[repository reloadRefs];
		[repository readCurrentBranch];
	}
	else
		[repository lazyReload];


	// Disable sorting for all columns
	for (NSTableColumn *column in [commitList tableColumns]) {
		[column setSortDescriptorPrototype:nil];
	}
	
	// Clear any existing sort descriptors
	[commitController setSortDescriptors:@[]];
	
	// Add a menu that allows a user to select which columns to view
	[[commitList headerView] setMenu:[self tableColumnMenu]];

	[historySplitView setTopMin:58.0 andBottomMin:100.0];
	[historySplitView setHidden:YES];
	
	// Defer split view setup to next run loop to ensure proper layout
	dispatch_async(dispatch_get_main_queue(), ^{
		[self restoreSplitViewPosition];
	});

	[upperToolbarView setTopShade:237.0f/255.0f bottomShade:216.0f/255.0f];
	
	// Always use All branches filter
	repository.currentBranchFilter = PBGitBranchFilterTypeAll;


	__weak typeof(self) weakSelf = self;
	commitList.findPanelActionBlock = ^(id sender) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		[strongSelf.view.window makeFirstResponder:strongSelf->searchField];
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
		// Don't reload the entire table on selection change - it loses the selection
		return;
	}

	if([strContext isEqualToString:@"branchChange"]) {
		return;
	}

	if([strContext isEqualToString:@"updateRefs"]) {
		[commitController rearrangeObjects];
		return;
	}

	if([strContext isEqualToString:@"updateCommitCount"] || [(__bridge NSString *)context isEqualToString:@"revisionListUpdating"]) {
		[self updateStatus];
		// Reload table view when commits change
		[commitList reloadData];

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

- (void)scrollSelectionToCenter
{
	NSInteger selectedRow = [commitList selectedRow];
	if (selectedRow == NSNotFound)
		return;
	
	NSRect visibleRect = [commitList visibleRect];
	NSRect rowRect = [commitList rectOfRow:selectedRow];
	
	// Calculate the center position
	CGFloat centerY = rowRect.origin.y + (rowRect.size.height / 2.0) - (visibleRect.size.height / 2.0);
	
	// Ensure we don't scroll past bounds
	if (centerY < 0)
		centerY = 0;
	
	NSPoint scrollPoint = NSMakePoint(0, centerY);
	[[commitList superview] scrollPoint:scrollPoint];
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
	
	// Also update the table view selection for view-based table
	NSIndexSet *selectionIndexes = [commitController selectionIndexes];
	if (selectionIndexes && [selectionIndexes count] > 0) {
		[commitList selectRowIndexes:selectionIndexes byExtendingSelection:NO];
	}

	[self scrollSelectionToTopOfViewFrom:oldIndex];

	forceSelectionUpdate = NO;
}

- (BOOL) hasNonlinearPath
{
	return [commitController filterPredicate] != nil;
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
	
	// Force layout of all subviews before unhiding
	[historySplitView setNeedsLayout:YES];
	[historySplitView layoutSubtreeIfNeeded];
	
	// Invalidate the intrinsic content size of subviews
	for (NSView *subview in [historySplitView subviews]) {
		[subview setNeedsLayout:YES];
		[subview setNeedsDisplay:YES];
	}
	
	[historySplitView setHidden:NO];
	
	// Force one more layout pass after unhiding
	[historySplitView setNeedsDisplay:YES];
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

#pragma mark - NSTableViewDelegate (View-Based)

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (tableView != commitList)
		return nil;
	
	NSArray *commits = [commitController arrangedObjects];
	if (row >= [commits count])
		return nil;
	
	PBGitCommit *commit = [commits objectAtIndex:row];
	
	NSString *identifier = [tableColumn identifier];
	
	if ([identifier isEqualToString:@"SubjectColumn"]) {
		PBGitRevisionCellView *cellView = [tableView makeViewWithIdentifier:@"SubjectCell" owner:self];
		if (!cellView) {
			cellView = [[PBGitRevisionCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 17)];
			cellView.identifier = @"SubjectCell";
			cellView.graphView.controller = self;
			cellView.graphView.contextMenuDelegate = refController;
		}
		
		PBGraphCellInfo *cellInfo = [commit lineInfo];
		[cellView configureForCommit:commit withCellInfo:cellInfo];
		
		return cellView;
	}
	else if ([identifier isEqualToString:@"AuthorColumn"]) {
		PBGitTableCellView *cellView = [tableView makeViewWithIdentifier:@"AuthorCell" owner:self];
		if (!cellView) {
			cellView = [[PBGitTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 17)];
			cellView.identifier = @"AuthorCell";
			
			NSTextField *textField = [NSTextField labelWithString:@""];
			textField.translatesAutoresizingMaskIntoConstraints = NO;
			textField.font = [NSFont systemFontOfSize:12];
			textField.lineBreakMode = NSLineBreakByTruncatingTail;
			[cellView addSubview:textField];
			cellView.textField = textField;
			
			[NSLayoutConstraint activateConstraints:@[
				[textField.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor constant:4],
				[textField.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor constant:-4],
				[textField.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor]
			]];
		}
		cellView.textField.stringValue = [commit author] ?: @"";
		// Text color will be handled by the table view's background style
		return cellView;
	}
	else if ([identifier isEqualToString:@"DateColumn"]) {
		PBGitTableCellView *cellView = [tableView makeViewWithIdentifier:@"DateCell" owner:self];
		if (!cellView) {
			cellView = [[PBGitTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 17)];
			cellView.identifier = @"DateCell";
			
			NSTextField *textField = [NSTextField labelWithString:@""];
			textField.translatesAutoresizingMaskIntoConstraints = NO;
			textField.font = [NSFont systemFontOfSize:12];
			textField.lineBreakMode = NSLineBreakByTruncatingTail;
			[cellView addSubview:textField];
			cellView.textField = textField;
			
			[NSLayoutConstraint activateConstraints:@[
				[textField.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor constant:4],
				[textField.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor constant:-4],
				[textField.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor]
			]];
		}
		
		static NSDateFormatter *dateFormatter = nil;
		if (!dateFormatter) {
			dateFormatter = [[NSDateFormatter alloc] init];
			[dateFormatter setDateStyle:NSDateFormatterShortStyle];
			[dateFormatter setTimeStyle:NSDateFormatterShortStyle];
		}
		
		cellView.textField.stringValue = [dateFormatter stringFromDate:[commit date]] ?: @"";
		// Text color will be handled by the table view's background style
		return cellView;
	}
	else if ([identifier isEqualToString:@"ShortSHAColumn"]) {
		PBGitTableCellView *cellView = [tableView makeViewWithIdentifier:@"ShortSHACell" owner:self];
		if (!cellView) {
			cellView = [[PBGitTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 17)];
			cellView.identifier = @"ShortSHACell";
			
			NSTextField *textField = [NSTextField labelWithString:@""];
			textField.translatesAutoresizingMaskIntoConstraints = NO;
			textField.font = [NSFont userFixedPitchFontOfSize:11];
			textField.lineBreakMode = NSLineBreakByTruncatingTail;
			[cellView addSubview:textField];
			cellView.textField = textField;
			
			[NSLayoutConstraint activateConstraints:@[
				[textField.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor constant:4],
				[textField.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor constant:-4],
				[textField.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor]
			]];
		}
		cellView.textField.stringValue = [commit shortName] ?: @"";
		// Text color will be handled by the table view's background style
		return cellView;
	}
	else if ([identifier isEqualToString:@"SHAColumn"]) {
		PBGitTableCellView *cellView = [tableView makeViewWithIdentifier:@"SHACell" owner:self];
		if (!cellView) {
			cellView = [[PBGitTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 17)];
			cellView.identifier = @"SHACell";
			
			NSTextField *textField = [NSTextField labelWithString:@""];
			textField.translatesAutoresizingMaskIntoConstraints = NO;
			textField.font = [NSFont userFixedPitchFontOfSize:11];
			textField.lineBreakMode = NSLineBreakByTruncatingTail;
			[cellView addSubview:textField];
			cellView.textField = textField;
			
			[NSLayoutConstraint activateConstraints:@[
				[textField.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor constant:4],
				[textField.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor constant:-4],
				[textField.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor]
			]];
		}
		cellView.textField.stringValue = [commit realSha] ?: @"";
		// Text color will be handled by the table view's background style
		return cellView;
	}
	
	return nil;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	if (tableView == commitList)
		return 17.0;
	return [tableView rowHeight];
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row
{
	if (tableView != commitList)
		return nil;
	
	PBCommitListRowView *rowView = [tableView makeViewWithIdentifier:@"RowView" owner:self];
	if (!rowView) {
		rowView = [[PBCommitListRowView alloc] init];
		rowView.identifier = @"RowView";
	}
	
	// Update search result status
	BOOL isSearchResult = [searchController isRowInSearchResults:row];
	BOOL isSelected = [commitList isRowSelected:row];
	
	rowView.isSearchResult = isSearchResult;
	rowView.isCurrentSearchResult = (isSearchResult && isSelected);
	
	return rowView;
}

- (void)tableView:(NSTableView *)tableView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row
{
	if (tableView != commitList)
		return;
	
	if ([rowView isKindOfClass:[PBCommitListRowView class]]) {
		PBCommitListRowView *commitRowView = (PBCommitListRowView *)rowView;
		
		// Update search result status
		BOOL isSearchResult = [searchController isRowInSearchResults:row];
		BOOL isSelected = [commitList isRowSelected:row];
		
		commitRowView.isSearchResult = isSearchResult;
		commitRowView.isCurrentSearchResult = (isSearchResult && isSelected);
	}
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	if (tableView == commitList)
		return [[commitController arrangedObjects] count];
	return 0;
}

#pragma mark - NSTableViewDelegate Selection

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	if (notification.object == commitList) {
		NSIndexSet *selectedRows = [commitList selectedRowIndexes];
		// Only update controller if the selection actually changed
		if (![selectedRows isEqualToIndexSet:[commitController selectionIndexes]]) {
			[commitController setSelectionIndexes:selectedRows];
		}
		
		// Update row highlighting for search results
		if ([searchController hasSearchResults]) {
			[commitList enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rowView, NSInteger row) {
				if ([rowView isKindOfClass:[PBCommitListRowView class]]) {
					PBCommitListRowView *commitRowView = (PBCommitListRowView *)rowView;
					BOOL isSearchResult = [searchController isRowInSearchResults:row];
					BOOL isSelected = [commitList isRowSelected:row];
					
					commitRowView.isSearchResult = isSearchResult;
					commitRowView.isCurrentSearchResult = (isSearchResult && isSelected);
					[commitRowView setNeedsDisplay:YES];
				}
			}];
		}
	}
}

#pragma mark - Context Menu

- (NSMenu *)menuForEvent:(NSEvent *)event
{
	NSPoint locationInWindow = [event locationInWindow];
	NSPoint locationInTable = [commitList convertPoint:locationInWindow fromView:nil];
	NSInteger row = [commitList rowAtPoint:locationInTable];
	
	if (row >= 0) {
		NSArray *commits = [commitController arrangedObjects];
		if (row < [commits count]) {
			PBGitCommit *commit = [commits objectAtIndex:row];
			
			NSArray *items = [refController menuItemsForCommit:commit];
			if (items) {
				NSMenu *menu = [[NSMenu alloc] init];
				[menu setAutoenablesItems:NO];
				for (NSMenuItem *item in items)
					[menu addItem:item];
				return menu;
			}
		}
	}
	
	return nil;
}




@end
