//
//  PBLabelController.m
//  GitX
//
//  Created by Pieter de Bie on 21-10-08.
//  Copyright 2008 Pieter de Bie. All rights reserved.
//

#import "PBRefController.h"
#import "PBGitRevisionCell.h"
#import "PBRefMenuItem.h"
#import "PBCreateBranchSheet.h"
#import "PBCreateTagSheet.h"
#import "PBGitDefaults.h"
#import "PBDiffWindowController.h"
#import "PBGitRevSpecifier.h"

#define kDialogAcceptDroppedRef @"Accept Dropped Ref"
#define kDialogDeleteRef @"Delete Ref"



@implementation PBRefController

- (void)awakeFromNib
{
	[commitList registerForDraggedTypes:[NSArray arrayWithObject:@"PBGitRef"]];
}




#pragma mark Merge

- (void) merge:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];
	[historyController.repository mergeWithRefish:refish];
}


#pragma mark Checkout

- (void) checkout:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];
	[historyController.repository checkoutRefish:refish];
}


#pragma mark Cherry Pick

- (void) cherryPick:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];
	[historyController.repository cherryPickRefish:refish];
}


#pragma mark Rebase

- (void) rebaseHeadBranch:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];

	[historyController.repository rebaseBranch:nil onRefish:refish];
}


#pragma mark Create Branch

- (void) createBranch:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];
	[PBCreateBranchSheet beginCreateBranchSheetAtRefish:refish inRepository:historyController.repository];
}


#pragma mark Copy info

- (void) copySHA:(PBRefMenuItem *)sender
{
	PBGitCommit *commit = nil;
	if ([[sender refish] refishType] == kGitXCommitType)
		commit = (PBGitCommit *)[sender refish];
	else
		commit = [historyController.repository commitForRef:[sender refish]];

	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
	[pasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
	[pasteboard setString:[commit realSha] forType:NSStringPboardType];
}


- (void) copyShortSHA:(PBRefMenuItem *)sender
{
	PBGitCommit *commit = nil;
	if ([[sender refish] refishType] == kGitXCommitType)
		commit = (PBGitCommit *)[sender refish];
	else
		commit = [historyController.repository commitForRef:[sender refish]];
    
	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
	[pasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
	[pasteboard setString:[commit shortName] forType:NSStringPboardType];
}


- (void) copyPatch:(PBRefMenuItem *)sender
{
	PBGitCommit *commit = nil;
	if ([[sender refish] refishType] == kGitXCommitType)
		commit = (PBGitCommit *)[sender refish];
	else
		commit = [historyController.repository commitForRef:[sender refish]];

	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
	[pasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
	[pasteboard setString:[commit patch] forType:NSStringPboardType];
}


#pragma mark Diff

- (void) diffWithHEAD:(PBRefMenuItem *)sender
{
	PBGitCommit *commit = nil;
	if ([[sender refish] refishType] == kGitXCommitType)
		commit = (PBGitCommit *)[sender refish];
	else
		commit = [historyController.repository commitForRef:[sender refish]];

	[PBDiffWindowController showDiffWindowWithFiles:nil fromCommit:commit diffCommit:nil];
}

#pragma mark Tags

- (void) createTag:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];
	[PBCreateTagSheet beginCreateTagSheetAtRefish:refish inRepository:historyController.repository];
}

- (void) showTagInfoSheet:(PBRefMenuItem *)sender
{
	if ([[sender refish] refishType] != kGitXTagType)
		return;

	NSString *tagName = [(PBGitRef *)[sender refish] tagName];
	NSString* title = [NSString stringWithFormat:@"Info for tag: %@", tagName];
	NSString* info = @"";
	
	// Use git tag -n to get tag annotation
	NSError *error = nil;
	NSString *output = [historyController.repository executeGitCommand:@[@"tag", @"-n", @"--", tagName] error:&error];
	
	if (!error && output) {
		output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		// Parse the output - git tag -n shows "tagname    message"
		NSArray *components = [output componentsSeparatedByString:@"\t"];
		if (components.count > 1) {
			info = [components objectAtIndex:1];
		} else {
			// Try splitting by spaces if no tab
			NSRange spaceRange = [output rangeOfString:@" "];
			if (spaceRange.location != NSNotFound) {
				info = [output substringFromIndex:spaceRange.location + 1];
			}
		}
	} else if (error) {
		NSLog(@"Couldn't look up tag %@: %@", tagName, error.localizedDescription);
	}
	
	[historyController.repository.windowController showMessageSheet:title infoText:info];
}


#pragma mark Remove a branch, remote or tag

- (void)showDeleteRefSheet:(PBRefMenuItem *)sender
{
	if ([[sender refish] refishType] == kGitXCommitType)
		return;

	PBGitRef *ref = (PBGitRef *)[sender refish];

	if ([PBGitDefaults isDialogWarningSuppressedForDialog:kDialogDeleteRef]) {
		[historyController.repository deleteRef:ref];
		return;
	}

	NSString *ref_desc = [NSString stringWithFormat:@"%@ '%@'", [ref refishType], [ref shortName]];

	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = [NSString stringWithFormat:@"Delete %@?", ref_desc];
	alert.informativeText = [NSString stringWithFormat:@"Are you sure you want to remove the %@?", ref_desc];
	[alert addButtonWithTitle:@"Delete"];
	[alert addButtonWithTitle:@"Cancel"];
	alert.showsSuppressionButton = YES;
	
	[alert beginSheetModalForWindow:[historyController.repository.windowController window] completionHandler:^(NSModalResponse returnCode) {
		if ([alert.suppressionButton state] == NSOnState)
			[PBGitDefaults suppressDialogWarningForDialog:kDialogDeleteRef];
		
		if (returnCode == NSAlertFirstButtonReturn || returnCode == NSModalResponseOK) {
			[historyController.repository deleteRef:ref];
		}
	}];
}




#pragma mark Contextual menus

- (NSArray *) menuItemsForRef:(PBGitRef *)ref
{
	return [PBRefMenuItem defaultMenuItemsForRef:ref inRepository:historyController.repository target:self];
}

- (NSArray *) menuItemsForCommit:(PBGitCommit *)commit
{
	return [PBRefMenuItem defaultMenuItemsForCommit:commit target:self];
}

- (NSArray *)menuItemsForRow:(NSInteger)rowIndex
{
	NSArray *commits = [commitController arrangedObjects];
	if ([commits count] <= rowIndex)
		return nil;

	return [self menuItemsForCommit:[commits objectAtIndex:(NSUInteger)rowIndex]];
}


# pragma mark Tableview delegate methods

- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
    
	NSPoint location = [(PBCommitList *)tv mouseDownPoint];
	NSInteger row = [tv rowAtPoint:location];
	NSInteger column = [tv columnAtPoint:location];
	NSInteger subjectColumn = [tv columnWithIdentifier:@"SubjectColumn"];
	if (column != subjectColumn)
		return NO;
	
	PBGitRevisionCell *cell = (PBGitRevisionCell *)[tv preparedCellAtColumn:column row:row];
	NSRect cellFrame = [tv frameOfCellAtColumn:column row:row];
	
	int index = [cell indexAtX:(float)(location.x - cellFrame.origin.x)];
	
	if (index == -1)
		return NO;

	PBGitRef *ref = [[[cell objectValue] refs] objectAtIndex:(NSUInteger)index];
	if ([ref isTag] || [ref isRemoteBranch])
		return NO;

	if ([[[historyController.repository headRef] ref] isEqualToRef:ref])
		return NO;
	
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[NSArray arrayWithObjects:[NSNumber numberWithInteger:row], [NSNumber numberWithInt:index], NULL]];
	[pboard declareTypes:[NSArray arrayWithObject:@"PBGitRef"] owner:self];
	[pboard setData:data forType:@"PBGitRef"];
	
	return YES;
}

- (NSDragOperation)tableView:(NSTableView*)tv
				validateDrop:(id <NSDraggingInfo>)info
				 proposedRow:(NSInteger)row
	   proposedDropOperation:(NSTableViewDropOperation)operation
{
	if (operation == NSTableViewDropAbove)
		return NSDragOperationNone;
	
	NSPasteboard *pboard = [info draggingPasteboard];
	if ([pboard dataForType:@"PBGitRef"])
		return NSDragOperationMove;
	
	return NSDragOperationNone;
}

- (void) dropRef:(NSDictionary *)dropInfo
{
	PBGitRef *ref = [dropInfo objectForKey:@"dragRef"];
	PBGitCommit *oldCommit = [dropInfo objectForKey:@"oldCommit"];
	PBGitCommit *dropCommit = [dropInfo objectForKey:@"dropCommit"];
	if (!ref || ! oldCommit || !dropCommit)
		return;

	NSError *error = nil;
	[historyController.repository executeGitCommand:[NSArray arrayWithObjects:@"update-ref", @"-mUpdate from GitX", [ref ref], [dropCommit realSha], NULL] error:&error];
	if (error)
		return;

	[dropCommit addRef:ref];
	[oldCommit removeRef:ref];
	[historyController.commitList reloadData];
}

- (BOOL)tableView:(NSTableView *)aTableView
	   acceptDrop:(id <NSDraggingInfo>)info
			  row:(NSInteger)row
	dropOperation:(NSTableViewDropOperation)operation
{
	if (operation != NSTableViewDropOn)
		return NO;
	
	NSPasteboard *pboard = [info draggingPasteboard];
	NSData *data = [pboard dataForType:@"PBGitRef"];
	if (!data)
		return NO;
	
	NSArray *numbers = [NSKeyedUnarchiver unarchiveObjectWithData:data];
	int oldRow = [[numbers objectAtIndex:0] intValue];
	if (oldRow == row)
		return NO;

	int oldRefIndex = [[numbers objectAtIndex:1] intValue];
	PBGitCommit *oldCommit = [[commitController arrangedObjects] objectAtIndex:(NSUInteger)oldRow];
	PBGitRef *ref = [[oldCommit refs] objectAtIndex:(NSUInteger)oldRefIndex];

	PBGitCommit *dropCommit = [[commitController arrangedObjects] objectAtIndex:(NSUInteger)row];

	NSDictionary *dropInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  ref, @"dragRef",
							  oldCommit, @"oldCommit",
							  dropCommit, @"dropCommit",
							  nil];

	if ([PBGitDefaults isDialogWarningSuppressedForDialog:kDialogAcceptDroppedRef]) {
		[self dropRef:dropInfo];
		return YES;
	}

	NSString *subject = [dropCommit subject];
	if ([subject length] > 99)
		subject = [[subject substringToIndex:99] stringByAppendingString:@"…"];
	NSString *infoText = [NSString stringWithFormat:@"Move the %@ to point to the commit: %@", [ref refishType], subject];

	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = [NSString stringWithFormat:@"Move %@: %@", [ref refishType], [ref shortName]];
	alert.informativeText = infoText;
	[alert addButtonWithTitle:@"Move"];
	[alert addButtonWithTitle:@"Cancel"];
	alert.showsSuppressionButton = YES;

	[alert beginSheetModalForWindow:[historyController.repository.windowController window] completionHandler:^(NSModalResponse returnCode) {
		if (returnCode == NSAlertFirstButtonReturn || returnCode == NSModalResponseOK)
			[self dropRef:dropInfo];
		
		if ([alert.suppressionButton state] == NSOnState)
			[PBGitDefaults suppressDialogWarningForDialog:kDialogAcceptDroppedRef];
	}];

	return YES;
}


- (void)dealloc {
    historyController = nil;
}

@end
