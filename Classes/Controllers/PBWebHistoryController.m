//
//  PBWebGitController.m
//  GitTest
//
//  Created by Pieter de Bie on 14-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBWebHistoryController.h"
#import "PBGitDefaults.h"
// #import <ObjectiveGit/GTConfiguration.h>
#import "PBGitRef.h"
#import "PBGitRevSpecifier.h"
#import "PBWebViewBridge.h"

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

	self.bridge.newWindowHandler = ^BOOL (PBWebViewBridge *bridge, NSURLRequest *request) {
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
	[[self script] setValue:nil forKey:@"commit"];
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
	if (content == nil || !finishedLoading)
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
	if (key.length == 0 || !finishedLoading)
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

	[super handleBridgeMessage:type payload:payload];
}

- (void) copySource
{
	NSString *source = [(DOMHTMLElement *)[[[view mainFrame] DOMDocument] documentElement] outerHTML];
	NSPasteboard *a =[NSPasteboard generalPasteboard];
	[a declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:self];
	[a setString:source forType: NSStringPboardType];
}

- (NSArray *)	   webView:(WebView *)sender
contextMenuItemsForElement:(NSDictionary *)element
		  defaultMenuItems:(NSArray *)defaultMenuItems
{
	DOMNode *node = [element valueForKey:@"WebElementDOMNode"];

	while (node) {
		// Every ref has a class name of 'refs' and some other class. We check on that to see if we pressed on a ref.
		if ([[node className] hasPrefix:@"refs "]) {
			NSString *selectedRefString = [[[node childNodes] item:0] textContent];
			for (PBGitRef *ref in historyController.webCommit.refs)
			{
				if ([[ref shortName] isEqualToString:selectedRefString])
					return [contextMenuDelegate menuItemsForRef:ref];
			}
			NSLog(@"Could not find selected ref!");
			return defaultMenuItems;
		}
		if ([node hasAttributes] && [[node attributes] getNamedItem:@"representedFile"])
			return nil;
        else if ([[node class] isEqual:[DOMHTMLImageElement class]]) {
            // Copy Image is the only menu item that makes sense here since we don't need
			// to download the image or open it in a new window (besides with the
			// current implementation these two entries can crash GitX anyway)
			for (NSMenuItem *item in defaultMenuItems)
				if ([item tag] == WebMenuItemTagCopyImageToClipboard)
					return [NSArray arrayWithObject:item];
			return nil;
        }

		node = [node parentNode];
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
