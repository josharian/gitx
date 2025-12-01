//
//  PBWebGitController.m
//  GitTest
//
//  Created by Pieter de Bie on 14-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBWebHistoryController.h"
#import "PBWebBridge.h"
#import "GitX-Swift.h"

@interface PBWebHistoryController ()
- (NSDictionary *)bridgeDictionaryForCommit:(PBGitCommit *)commit currentRef:(NSString *)currentRef;
- (NSArray *)bridgeRefsForCommit:(PBGitCommit *)commit;
@end

@implementation PBWebHistoryController

@synthesize diff;

- (void) awakeFromNib
{
	startFile = @"history";
	repository = historyController.repository;
	[super awakeFromNib];

	self.bridge.newWindowHandler = ^BOOL (id<PBWebBridge> bridge, NSURLRequest *request) {
		NSURL *url = request.URL;
		if (!url) {
			return NO;
		}
		[[NSWorkspace sharedWorkspace] openURL:url];
		return YES;
	};
	[historyController addObserver:self forKeyPath:@"webCommit" options:0 context:@"ChangedCommit"];
}

- (void)closeView
{
	[historyController removeObserver:self forKeyPath:@"webCommit"];

	[super closeView];
}

- (void) didLoad
{
	currentSha = nil;
	[self changeContentTo: historyController.webCommit];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([(__bridge NSString *)context isEqualToString: @"ChangedCommit"])
		[self changeContentTo: historyController.webCommit];
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void) changeContentTo: (PBGitCommit *) content
{
	if (content == nil)
		return;

	NSString *headRef = [[[historyController repository] headRef] simpleRef];
	NSDictionary *commitPayload = [self bridgeDictionaryForCommit:content currentRef:headRef];
	NSString *sha = commitPayload[@"sha"] ?: @"";

	if ([currentSha isEqualToString:sha]) {
		[self sendBridgeEventWithType:@"commitRefsUpdated" payload:@{ @"commit": commitPayload ?: @{}, @"sha": sha ?: @"" }];
		return;
	}

	[self sendBridgeEventWithType:@"commitSelected"
					 payload:@{ @"commit": commitPayload ?: @{},
							@"currentRef": headRef ?: @"",
							@"sha": sha ?: @"" }];
	currentSha = sha;

	// Now we load the extended details. We used to do this in a separate thread,
	// but this caused some funny behaviour because NSTask's and NSThread's don't really
	// like each other. Instead, just do it async.

	NSMutableArray *taskArguments = [NSMutableArray arrayWithObjects:@"show", @"--pretty=raw", @"-M", @"--no-color", currentSha, nil];
	if (![PBGitDefaults showWhitespaceDifferences])
		[taskArguments insertObject:@"-w" atIndex:1];

	NSFileHandle *handle = [repository handleForArguments:taskArguments];
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	// Remove notification, in case we have another one running
	[nc removeObserver:self name:NSFileHandleReadToEndOfFileCompletionNotification object:nil];
	[nc addObserver:self selector:@selector(commitDetailsLoaded:) name:NSFileHandleReadToEndOfFileCompletionNotification object:handle]; 
	[handle readToEndOfFileInBackgroundAndNotify];
}

- (void)commitDetailsLoaded:(NSNotification *)notification
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadToEndOfFileCompletionNotification object:nil];

	NSData *data = [[notification userInfo] valueForKey:NSFileHandleNotificationDataItem];
	if (!data)
		return;

	NSString *details = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!details)
		details = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];

	if (!details)
		return;

	NSDictionary *payload = @{ @"sha": currentSha ?: @"", @"details": details ?: @"" };
	[self sendBridgeEventWithType:@"commitDetails" payload:payload];
}

- (void)selectCommit:(NSString *)sha
{
	// Validate SHA using git rev-parse before creating PBCommitID
	NSError *error = nil;
	NSString *validatedSHA = [historyController.repository executeGitCommand:@[@"rev-parse", @"--verify", [NSString stringWithFormat:@"%@^{commit}", sha]] error:&error];
	
	if (!error && validatedSHA) {
		validatedSHA = [validatedSHA stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		NSString *oid = validatedSHA;
		[historyController selectCommit: oid];
	} else {
		if (error) {
			NSLog(@"Error validating commit SHA %@: %@", sha, error.localizedDescription);
		} else {
			NSLog(@"Invalid commit SHA: %@", sha);
		}
		// Fallback to original behavior for compatibility
		NSString *oid = sha;
		[historyController selectCommit: oid];
	}
}

- (void) sendKey: (NSString*) key
{
	if (key.length == 0)
		return;

	NSDictionary *payload = @{ @"key": key ?: @"" };
	[self sendBridgeEventWithType:@"historyKeyCommand" payload:payload];
}

- (void)handleBridgeMessage:(NSString *)type payload:(NSDictionary *)payload
{
	if ([type isEqualToString:@"selectCommit"]) {
		NSString *sha = payload[@"sha"];
		if ([sha isKindOfClass:[NSString class]] && sha.length > 0) {
			[self selectCommit:sha];
		} else {
			NSLog(@"PBWebHistoryController: selectCommit payload missing sha: %@", payload);
		}
		return;
	}

	if ([type isEqualToString:@"copySource"]) {
		[self copySource];
		return;
	}

	[super handleBridgeMessage:type payload:payload];
}

- (void) copySource
{
	static NSString *const kCopySourceScript = @"(function(){\n"
		"  if (!document || !document.documentElement) { return ''; }\n"
		"  return document.documentElement.outerHTML;\n"
		"})();";

	[self.bridge evaluateJavaScript:kCopySourceScript completion:^(id result, NSError *error) {
		if (error) {
			NSLog(@"PBWebHistoryController: Failed to copy source: %@", error);
			return;
		}

		NSString *source = nil;
		if ([result isKindOfClass:[NSString class]]) {
			source = result;
		} else if ([result respondsToSelector:@selector(description)]) {
			source = [result description];
		}

		if (source.length == 0) {
			return;
		}

			dispatch_async(dispatch_get_main_queue(), ^{
				NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
				[pasteboard declareTypes:@[NSPasteboardTypeString] owner:self];
				[pasteboard setString:source forType:NSPasteboardTypeString];
		});
	}];
}

- (NSArray *)contextMenuItemsForBridge:(id<PBWebBridge>)bridge elementInfo:(NSDictionary *)elementInfo defaultMenuItems:(NSArray *)defaultMenuItems
{
	#pragma unused(bridge)
	NSString *type = [[elementInfo[@"type"] description] lowercaseString];
	if ([type isEqualToString:@"refs"]) {
		NSString *selectedRefString = [elementInfo[@"refText"] description];
		if (selectedRefString.length > 0) {
			for (PBGitRef *ref in historyController.webCommit.refs) {
				if ([[ref shortName] isEqualToString:selectedRefString]) {
					return [contextMenuDelegate menuItemsForRef:ref];
				}
			}
			NSLog(@"Could not find selected ref for context menu: %@", selectedRefString);
		}
		return defaultMenuItems;
	}

	if ([type isEqualToString:@"representedfile"]) {
		return nil;
	}

	if ([type isEqualToString:@"image"]) {
		NSMutableArray *filtered = [NSMutableArray array];
		for (NSMenuItem *item in defaultMenuItems) {
			SEL action = item.action;
			BOOL isCopyAction = (action == @selector(copy:)) || (action == NSSelectorFromString(@"copyImageToClipboard:"));
			BOOL titleIndicatesCopy = [[item title] rangeOfString:@"copy" options:NSCaseInsensitiveSearch].location != NSNotFound;
			if (isCopyAction || titleIndicatesCopy) {
				[filtered addObject:item];
			}
		}
		return filtered.count ? [filtered copy] : nil;
	}

	return defaultMenuItems;
}

- (NSDictionary *)bridgeDictionaryForCommit:(PBGitCommit *)commit currentRef:(NSString *)currentRef
{
	if (!commit)
		return @{};

	NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
	NSString *sha = [commit realSha] ?: [commit sha] ?: @"";
	dictionary[@"sha"] = sha;
	if (sha.length >= 1) {
		NSUInteger shortLength = MIN((NSUInteger)7, sha.length);
		dictionary[@"shortSha"] = [sha substringToIndex:shortLength];
	} else {
		dictionary[@"shortSha"] = @"";
	}

	dictionary[@"subject"] = [commit subject] ?: @"";
	dictionary[@"authorName"] = [commit author] ?: @"";
	dictionary[@"committerName"] = [commit committer] ?: @"";
	NSArray *parents = [commit parents];
	dictionary[@"parents"] = parents ? [parents copy] : @[];
	dictionary[@"refs"] = [self bridgeRefsForCommit:commit];
	dictionary[@"currentRef"] = currentRef ?: @"";

	return dictionary;
}

- (NSArray *)bridgeRefsForCommit:(PBGitCommit *)commit
{
	NSArray *refs = [commit refs];
	if (![refs count])
		return @[];

	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[refs count]];
	for (PBGitRef *ref in refs) {
		if (![ref isKindOfClass:[PBGitRef class]])
			continue;

		NSString *refName = [ref refishName] ?: @"";
		NSString *shortName = [ref shortName];
		if (!shortName || shortName.length == 0)
			shortName = refName;

		NSMutableDictionary *serializedRef = [NSMutableDictionary dictionary];
		serializedRef[@"ref"] = refName;
		serializedRef[@"shortName"] = shortName ?: @"";
		serializedRef[@"type"] = [ref type] ?: @"";
		serializedRef[@"refType"] = [ref refishType] ?: @"";

		[result addObject:serializedRef];
	}

	return result;
}

- getConfig:(NSString *)key
{
	NSError *error = nil;
	NSString *value = [historyController.repository executeGitCommand:@[@"config", @"--get", key] error:&error];
	
	if (!error && value) {
		return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	}
	
	return nil;
}



@end
