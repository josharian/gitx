//
//  PBWebChangesController.m
//  GitX
//
//  Created by Pieter de Bie on 22-09-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBWebChangesController.h"
#import "PBGitIndexController.h"
#import "PBGitIndex.h"

@interface PBWebChangesController ()
- (NSDictionary *)bridgeDictionaryForChangedFile:(PBChangedFile *)file;
@end

@implementation PBWebChangesController

- (void) awakeFromNib
{
	selectedFile = nil;
	selectedFileIsCached = NO;

	startFile = @"commit";
	[super awakeFromNib];

	[unstagedFilesController addObserver:self forKeyPath:@"selection" options:0 context:@"UnstagedFileSelected"];
	[cachedFilesController addObserver:self forKeyPath:@"selection" options:0 context:@"cachedFileSelected"];
}

- (void)closeView
{
	[[self script] removeWebScriptKey:@"Index"];
	[unstagedFilesController removeObserver:self forKeyPath:@"selection"];
	[cachedFilesController removeObserver:self forKeyPath:@"selection"];

	[super closeView];
}

- (void) didLoad
{
	[[self script] setValue:controller.index forKey:@"Index"];
	[self refresh];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object
						change:(NSDictionary *)change
					   context:(void *)context
{
	NSArrayController *otherController;
	otherController = object == unstagedFilesController ? cachedFilesController : unstagedFilesController;
	NSUInteger count = [[object selectedObjects] count];
	if (count == 0) {
		if([[otherController selectedObjects] count] == 0 && selectedFile) {
			selectedFile = nil;
			selectedFileIsCached = NO;
			[self refresh];
		}
		return;
	}

	// TODO: Move this to commitcontroller
	[otherController setSelectionIndexes:[NSIndexSet indexSet]];

	if (count > 1) {
		[self showMultiple: [object selectedObjects]];
		return;
	}

	selectedFile = [[object selectedObjects] objectAtIndex:0];
	selectedFileIsCached = object == cachedFilesController;

	[self refresh];
}

- (void) showMultiple: (NSArray *)objects
{
	if (!finishedLoading)
		return;

	NSMutableArray *filesPayload = [NSMutableArray arrayWithCapacity:[objects count]];
	for (id file in objects) {
		NSString *path = nil;
		if ([file isKindOfClass:[PBChangedFile class]])
			path = [(PBChangedFile *)file path];
		else if ([file respondsToSelector:@selector(path)])
			path = [file valueForKey:@"path"];

		if (!path)
			path = @"";

		[filesPayload addObject:@{ @"path": path }];
	}

	NSDictionary *payload = @{ @"files": filesPayload };
	[self sendBridgeEventWithType:@"commitMultipleSelection" payload:payload];
}

- (void) refresh
{
	if (!finishedLoading)
		return;

	NSMutableDictionary *payload = [NSMutableDictionary dictionary];
	payload[@"cached"] = @(selectedFileIsCached);
	if (selectedFile)
		payload[@"file"] = [self bridgeDictionaryForChangedFile:selectedFile];

	[self sendBridgeEventWithType:@"commitSelectionChanged" payload:payload];
}

- (void)stageHunk:(NSString *)hunk reverse:(BOOL)reverse
{
	[controller.index applyPatch:hunk stage:YES reverse:reverse];
	// FIXME: Don't need a hard refresh

	[self refresh];
}

- (void) discardHunk:(NSString *)hunk
{
    [controller.index applyPatch:hunk stage:NO reverse:YES];
    [self refresh];
}


- (void)discardHunk:(NSString *)hunk altKey:(BOOL)altKey
{
	if (!altKey) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Discard hunk"];
        [alert setInformativeText:@"Are you sure you wish to discard the changes in this hunk?\n\nYou cannot undo this operation."];
        [alert addButtonWithTitle:@"Discard"];
        [alert addButtonWithTitle:@"Cancel"];
		[alert beginSheetModalForWindow:[[controller view] window] completionHandler:^(NSModalResponse returnCode) {
			if (returnCode == NSAlertFirstButtonReturn || returnCode == NSModalResponseOK) {
				[self discardHunk:hunk];
			}
		}];
	} else {
        [self discardHunk:hunk];
    }
}

- (void) setStateMessage:(NSString *)state
{
	if (!finishedLoading)
		return;

	NSDictionary *payload = @{ @"state": state ?: @"" };
	[self sendBridgeEventWithType:@"commitState" payload:payload];
}

- (NSDictionary *)bridgeDictionaryForChangedFile:(PBChangedFile *)file
{
	if (!file)
		return @{};

	NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
	NSString *path = file.path ?: @"";
	dictionary[@"path"] = path;
	dictionary[@"status"] = @(file.status);
	dictionary[@"hasStagedChanges"] = @(file.hasStagedChanges);
	dictionary[@"hasUnstagedChanges"] = @(file.hasUnstagedChanges);
	dictionary[@"commitBlobSHA"] = file.commitBlobSHA ?: @"";
	dictionary[@"commitBlobMode"] = file.commitBlobMode ?: @"";

	return dictionary;
}

- (void)handleBridgeMessage:(NSString *)type payload:(NSDictionary *)payload
{
	if ([type isEqualToString:@"commitApplyPatch"]) {
		NSString *patch = nil;
		id patchValue = payload[@"patch"];
		if ([patchValue isKindOfClass:[NSString class]])
			patch = patchValue;
		else if ([patchValue respondsToSelector:@selector(description)])
			patch = [patchValue description];
		if (patch.length == 0)
			return;

		BOOL reverse = NO;
		id reverseValue = payload[@"reverse"];
		if ([reverseValue respondsToSelector:@selector(boolValue)])
			reverse = [reverseValue boolValue];

		BOOL stage = YES;
		id stageValue = payload[@"stage"];
		if ([stageValue respondsToSelector:@selector(boolValue)])
			stage = [stageValue boolValue];

		[controller.index applyPatch:patch stage:stage reverse:reverse];
		[self refresh];
		return;
	}

	if ([type isEqualToString:@"commitDiscardHunk"]) {
		NSString *patch = nil;
		id patchValue = payload[@"patch"];
		if ([patchValue isKindOfClass:[NSString class]])
			patch = patchValue;
		else if ([patchValue respondsToSelector:@selector(description)])
			patch = [patchValue description];
		if (patch.length == 0)
			return;

		BOOL altKey = NO;
		id altValue = payload[@"altKey"];
		if ([altValue respondsToSelector:@selector(boolValue)])
			altKey = [altValue boolValue];

		[self discardHunk:patch altKey:altKey];
		return;
	}

	if ([type isEqualToString:@"requestCommitDiff"]) {
		if (!selectedFile)
			return;

		NSString *requestedPath = nil;
		id pathValue = payload[@"path"];
		if ([pathValue isKindOfClass:[NSString class]])
			requestedPath = pathValue;
		else if ([pathValue respondsToSelector:@selector(description)])
			requestedPath = [pathValue description];

		NSString *currentPath = selectedFile.path ?: @"";
		if (requestedPath && ![requestedPath isEqualToString:currentPath])
			return;

		NSUInteger contextLines = 0;
		id contextValue = payload[@"contextLines"];
		if ([contextValue respondsToSelector:@selector(unsignedIntegerValue)])
			contextLines = [contextValue unsignedIntegerValue];
		else if ([contextValue respondsToSelector:@selector(integerValue)])
			contextLines = (NSUInteger)MAX(0, [contextValue integerValue]);

		NSString *diff = [controller.index diffForFile:selectedFile staged:selectedFileIsCached contextLines:contextLines];
		BOOL isBinary = (diff == nil);
		if (!diff)
			diff = @"";

		NSMutableDictionary *response = [NSMutableDictionary dictionary];
		response[@"path"] = currentPath ?: @"";
		response[@"cached"] = @(selectedFileIsCached);
		response[@"contextLines"] = @(contextLines);
		response[@"diff"] = diff;
		response[@"isBinary"] = @(isBinary);
		response[@"isNewFile"] = @((selectedFile.status == NEW));

		[self sendBridgeEventWithType:@"commitDiff" payload:response];
		return;
	}

	[super handleBridgeMessage:type payload:payload];
}

@end
