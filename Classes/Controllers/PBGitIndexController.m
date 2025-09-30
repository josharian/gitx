//
//  PBGitIndexController.m
//  GitX
//
//  Created by Pieter de Bie on 18-11-08.
//  Copyright 2008 Pieter de Bie. All rights reserved.
//

#import "PBGitIndexController.h"
#import "GitX-Swift.h"
#import "PBGitRepository.h"
#import "PBGitIndex.h"


@interface PBGitIndexController ()
- (void)discardChangesForFiles:(NSArray *)files force:(BOOL)force;
- (BOOL)trashFiles:(NSArray *)files;
@end

@implementation PBGitIndexController

- (void)awakeFromNib
{
	[unstagedTable setDoubleAction:@selector(tableClicked:)];
	[stagedTable setDoubleAction:@selector(tableClicked:)];

	[unstagedTable setTarget:self];
	[stagedTable setTarget:self];

}

// FIXME: Find a proper place for this method -- this is not it.
- (void)ignoreFiles:(NSArray *)files
{
	// Build output string
	NSMutableArray *fileList = [NSMutableArray array];
	for (PBChangedFile *file in files) {
		NSString *name = file.path;
		if ([name length] > 0)
			[fileList addObject:name];
	}
	NSString *filesAsString = [fileList componentsJoinedByString:@"\n"];

	// Write to the file
	NSString *gitIgnoreName = [commitController.repository gitIgnoreFilename];

	NSStringEncoding enc = NSUTF8StringEncoding;
	NSError *error = nil;
	NSMutableString *ignoreFile;

	if (![[NSFileManager defaultManager] fileExistsAtPath:gitIgnoreName]) {
		ignoreFile = [filesAsString mutableCopy];
	} else {
		ignoreFile = [NSMutableString stringWithContentsOfFile:gitIgnoreName usedEncoding:&enc error:&error];
		if (error) {
			[[commitController.repository windowController] showErrorSheet:error];
			return;
		}
		// Add a newline if not yet present
		if ([ignoreFile characterAtIndex:([ignoreFile length] - 1)] != '\n')
			[ignoreFile appendString:@"\n"];
		[ignoreFile appendString:filesAsString];
	}

	[ignoreFile writeToFile:gitIgnoreName atomically:YES encoding:enc error:&error];
	if (error)
		[[commitController.repository windowController] showErrorSheet:error];
}

# pragma mark Context Menu methods
- (BOOL) allSelectedCanBeIgnored:(NSArray *)selectedFiles
{
	if ([selectedFiles count] == 0)
	{
		return NO;
	}
	for (PBChangedFile *selectedItem in selectedFiles) {
		if (selectedItem.status != PBChangedFileStatusNew) {
			return NO;
		}
	}
	return YES;
}

- (NSMenu *) menuForTable:(NSTableView *)table
{
	NSMenu *menu = [[NSMenu alloc] init];
	id controller = [table tag] == 0 ? unstagedFilesController : stagedFilesController;
	NSArray *selectedFiles = [controller selectedObjects];
	
	if ([selectedFiles count] == 0)
	{
		return menu;
	}

	// Unstaged changes
	if ([table tag] == 0) {
		NSMenuItem *stageItem = [[NSMenuItem alloc] initWithTitle:@"Stage Changes" action:@selector(stageFilesAction:) keyEquivalent:@"s"];
		[stageItem setTarget:self];
		[stageItem setRepresentedObject:selectedFiles];
		[menu addItem:stageItem];
	}
	else if ([table tag] == 1) {
		NSMenuItem *unstageItem = [[NSMenuItem alloc] initWithTitle:@"Unstage Changes" action:@selector(unstageFilesAction:) keyEquivalent:@"u"];
		[unstageItem setTarget:self];
		[unstageItem setRepresentedObject:selectedFiles];
		[menu addItem:unstageItem];
	}

	NSString *title = [selectedFiles count] == 1 ? @"Open file" : @"Open files";
	NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:title action:@selector(openFilesAction:) keyEquivalent:@""];
	[openItem setTarget:self];
	[openItem setRepresentedObject:selectedFiles];
	[menu addItem:openItem];

	NSMenuItem *openInVSCodeItem = [[NSMenuItem alloc] initWithTitle:@"Open in VSCode" action:@selector(openFilesInVSCodeAction:) keyEquivalent:@""];
	[openInVSCodeItem setTarget:self];
	[openInVSCodeItem setRepresentedObject:selectedFiles];
	[menu addItem:openInVSCodeItem];

	// Attempt to ignore
	if ([self allSelectedCanBeIgnored:selectedFiles]) {
		NSString *ignoreText = [selectedFiles count] == 1 ? @"Ignore File": @"Ignore Files";
		NSMenuItem *ignoreItem = [[NSMenuItem alloc] initWithTitle:ignoreText action:@selector(ignoreFilesAction:) keyEquivalent:@""];
		[ignoreItem setTarget:self];
		[ignoreItem setRepresentedObject:selectedFiles];
		[menu addItem:ignoreItem];
	}

	if ([selectedFiles count] == 1) {
		NSMenuItem *showInFinderItem = [[NSMenuItem alloc] initWithTitle:@"Show in Finder" action:@selector(showInFinderAction:) keyEquivalent:@""];
		[showInFinderItem setTarget:self];
		[showInFinderItem setRepresentedObject:selectedFiles];
		[menu addItem:showInFinderItem];
    }

	BOOL hasTrackedChanges = NO;
	BOOL hasNewFiles = NO;
	for (PBChangedFile *file in selectedFiles)
	{
		if (file.status == PBChangedFileStatusNew)
		{
			hasNewFiles = YES;
		}
		else if (file.hasUnstagedChanges)
		{
			hasTrackedChanges = YES;
		}
	}

	if (!hasTrackedChanges && !hasNewFiles)
	{
		return menu;
	}

	if (hasTrackedChanges && hasNewFiles)
	{
		NSMenuItem *combinedItem = [[NSMenuItem alloc] initWithTitle:@"Discard/Delete…" action:@selector(discardFilesAction:) keyEquivalent:@""];
		[combinedItem setTarget:self];
		[combinedItem setAlternate:NO];
		[combinedItem setRepresentedObject:selectedFiles];
		[menu addItem:combinedItem];

		NSMenuItem *combinedForceItem = [[NSMenuItem alloc] initWithTitle:@"Discard/Delete" action:@selector(forceDiscardFilesAction:) keyEquivalent:@""];
		[combinedForceItem setTarget:self];
		[combinedForceItem setAlternate:YES];
		[combinedForceItem setRepresentedObject:selectedFiles];
		[combinedForceItem setKeyEquivalentModifierMask:NSEventModifierFlagOption];
		[menu addItem:combinedForceItem];
	}
	else if (hasTrackedChanges)
	{
		NSMenuItem *discardItem = [[NSMenuItem alloc] initWithTitle:@"Discard changes…" action:@selector(discardFilesAction:) keyEquivalent:@""];
		[discardItem setTarget:self];
		[discardItem setAlternate:NO];
		[discardItem setRepresentedObject:selectedFiles];
		[menu addItem:discardItem];

		NSMenuItem *discardForceItem = [[NSMenuItem alloc] initWithTitle:@"Discard changes" action:@selector(forceDiscardFilesAction:) keyEquivalent:@""];
		[discardForceItem setTarget:self];
		[discardForceItem setAlternate:YES];
		[discardForceItem setRepresentedObject:selectedFiles];
		[discardForceItem setKeyEquivalentModifierMask:NSEventModifierFlagOption];
		[menu addItem:discardForceItem];
	}
	else if (hasNewFiles)
	{
		NSMenuItem *moveToTrashItem = [[NSMenuItem alloc] initWithTitle:@"Move to Trash" action:@selector(moveToTrashAction:) keyEquivalent:@""];
		[moveToTrashItem setTarget:self];
		[moveToTrashItem setRepresentedObject:selectedFiles];
		[menu addItem:moveToTrashItem];
	}

	return menu;
}

- (void) stageSelectedFiles
{
	[commitController.index stageFiles:[unstagedFilesController selectedObjects]];
}

- (void) unstageSelectedFiles
{
	[commitController.index unstageFiles:[stagedFilesController selectedObjects]];
}


- (void) stageFilesAction:(id) sender
{
	[commitController.index stageFiles:[sender representedObject]];
}

- (void) unstageFilesAction:(id) sender
{
	[commitController.index unstageFiles:[sender representedObject]];
}

- (void) openFilesAction:(id) sender
{
	NSArray *files = [sender representedObject];
	NSString *workingDirectory = [commitController.repository workingDirectory];
	for (PBChangedFile *file in files)
		[[NSWorkspace sharedWorkspace] openFile:[workingDirectory stringByAppendingPathComponent:[file path]]];
}

- (void) openFilesInVSCodeAction:(id)sender
{
	NSArray *files = [sender representedObject];
	if ([files count] == 0)
		return;

	NSString *workingDirectory = [commitController.repository workingDirectory];
	NSMutableArray<NSString *> *arguments = [NSMutableArray array];
	[arguments addObject:@"code"];

	for (PBChangedFile *file in files) {
		NSString *fullPath = [workingDirectory stringByAppendingPathComponent:[file path]];
		if (fullPath != nil) {
			[arguments addObject:fullPath];
		}
	}

	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath:@"/usr/bin/env"];
	[task setArguments:arguments];
	@try {
		[task launch];
	}
	@catch (NSException *exception) {
		NSLog(@"Failed to launch VSCode: %@", exception);
	}
}

- (void) ignoreFilesAction:(id) sender
{
	NSArray *selectedFiles = [sender representedObject];
	if ([selectedFiles count] == 0)
		return;

	[self ignoreFiles:selectedFiles];
	[commitController.index refresh];
}

- (void)discardFilesAction:(id) sender
{
	NSArray *selectedFiles = [sender representedObject];
	if ([selectedFiles count] > 0)
		[self discardChangesForFiles:selectedFiles force:FALSE];
}

- (void)forceDiscardFilesAction:(id) sender
{
	NSArray *selectedFiles = [sender representedObject];
	if ([selectedFiles count] > 0)
		[self discardChangesForFiles:selectedFiles force:TRUE];
}

- (void) showInFinderAction:(id) sender
{
	NSArray *selectedFiles = [sender representedObject];
	if ([selectedFiles count] == 0)
		return;
	NSString *workingDirectory = [[commitController.repository workingDirectory] stringByAppendingString:@"/"];
	NSString *path = [workingDirectory stringByAppendingPathComponent:[[selectedFiles objectAtIndex:0] path]];
	NSWorkspace *ws = [NSWorkspace sharedWorkspace];
	[ws selectFile: path inFileViewerRootedAtPath:@""];
}

- (BOOL)trashFiles:(NSArray *)files
{
	if ([files count] == 0)
		return NO;

	NSString *workingDirectory = [commitController.repository workingDirectory];
	NSURL *workDirURL = [NSURL fileURLWithPath:workingDirectory isDirectory:YES];

	BOOL anyTrashed = NO;
	for (PBChangedFile *file in files)
	{
		NSURL *fileURL = [workDirURL URLByAppendingPathComponent:[file path]];
		NSError *error = nil;
		if ([[NSFileManager defaultManager] trashItemAtURL:fileURL
									  resultingItemURL:nil
										   error:&error])
		{
			anyTrashed = YES;
		}
	}

	return anyTrashed;
}

- (void)moveToTrashAction:(id)sender
{
	NSArray *selectedFiles = [sender representedObject];
	if ([selectedFiles count] == 0)
		return;

	if ([self trashFiles:selectedFiles])
	{
		[commitController.index refresh];
	}
}


- (void) discardChangesForFiles:(NSArray *)files force:(BOOL)force
{
	NSMutableArray *filesToDiscard = [NSMutableArray array];
	NSMutableArray *filesToTrash = [NSMutableArray array];

	for (PBChangedFile *file in files)
	{
		if (file.status == PBChangedFileStatusNew)
		{
			[filesToTrash addObject:file];
		}
		else
		{
			[filesToDiscard addObject:file];
		}
	}

	if ([filesToDiscard count] == 0 && [filesToTrash count] == 0)
		return;

	void (^performDiscardOrDelete)(void) = ^{
		if ([filesToDiscard count] > 0)
		{
			[commitController.index discardChangesForFiles:filesToDiscard];
		}

		if ([filesToTrash count] > 0 && [self trashFiles:filesToTrash])
		{
			[commitController.index refresh];
		}
	};

	BOOL requiresConfirmation = (!force && ([filesToDiscard count] > 0 || [filesToTrash count] > 0));
	if (requiresConfirmation)
	{
		NSAlert *alert = [[NSAlert alloc] init];
		NSString *messageText = nil;
		NSString *informativeText = nil;
		NSString *primaryButtonTitle = nil;

		if ([filesToDiscard count] > 0 && [filesToTrash count] > 0)
		{
			messageText = @"Discard tracked changes and delete new files";
			informativeText = @"Are you sure you wish to discard the changes to tracked files and delete the selected new files?\n\nYou cannot undo this operation.";
			primaryButtonTitle = @"Discard & Delete";
		}
		else if ([filesToDiscard count] > 0)
		{
			messageText = @"Discard changes";
			informativeText = @"Are you sure you wish to discard the changes to the selected files?\n\nYou cannot undo this operation.";
			primaryButtonTitle = @"Discard";
		}
		else
		{
			messageText = @"Delete files";
			informativeText = @"Are you sure you wish to delete the selected files?\n\nYou cannot undo this operation.";
			primaryButtonTitle = @"Delete";
		}

		alert.messageText = messageText;
		alert.informativeText = informativeText;
		[alert addButtonWithTitle:primaryButtonTitle];
		[alert addButtonWithTitle:@"Cancel"];
		
		[alert beginSheetModalForWindow:[[commitController view] window] completionHandler:^(NSModalResponse returnCode) {
			if (returnCode == NSAlertFirstButtonReturn || returnCode == NSModalResponseOK)
			{
				performDiscardOrDelete();
			}
		}];
	}
	else
	{
		performDiscardOrDelete();
	}
}

# pragma mark TableView icon delegate
- (void)tableView:(NSTableView*)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)rowIndex
{
	id controller = [tableView tag] == 0 ? unstagedFilesController : stagedFilesController;
	[[tableColumn dataCell] setImage:[[[controller arrangedObjects] objectAtIndex:(NSUInteger)rowIndex] icon]];
}

- (void) tableClicked:(NSTableView *) tableView
{
	NSArrayController *controller = [tableView tag] == 0 ? unstagedFilesController : stagedFilesController;

	NSIndexSet *selectionIndexes = [tableView selectedRowIndexes];
	NSArray *files = [[controller arrangedObjects] objectsAtIndexes:selectionIndexes];
	if ([tableView tag] == 0)
		[commitController.index stageFiles:files];
	else
		[commitController.index unstageFiles:files];
}

- (void) rowClicked:(NSCell *)sender
{
	NSTableView *tableView = (NSTableView *)[sender controlView];
	if([tableView numberOfSelectedRows] != 1)
		return;
	[self tableClicked: tableView];
}




@end
