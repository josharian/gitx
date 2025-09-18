//
//  PBWebController.m
//  GitX
//
//  Created by Pieter de Bie on 08-10-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBWebController.h"
#import "PBGitRepository.h"
#import "PBGitXProtocol.h"
#import "PBGitDefaults.h"
#import "PBWebViewBridge.h"

#include <SystemConfiguration/SCNetworkReachability.h>

@interface PBWebController()
@property (nonatomic, strong) PBWebViewBridge *bridge;
- (void)installJavaScriptBridgeHelpers;
@end

@implementation PBWebController

@synthesize startFile, repository, bridge = _bridge;

- (void) awakeFromNib
{
	callbacks = [NSMapTable mapTableWithKeyOptions:(NSPointerFunctionsObjectPointerPersonality|NSPointerFunctionsStrongMemory) valueOptions:(NSPointerFunctionsObjectPointerPersonality|NSPointerFunctionsStrongMemory)];

	finishedLoading = NO;

	NSBundle *bundle = [NSBundle mainBundle];
	self.bridge = [[PBWebViewBridge alloc] initWithWebView:view bundle:bundle];

	__weak typeof(self) weakSelf = self;
	self.bridge.didClearWindowObjectHandler = ^(PBWebViewBridge *bridge, WebScriptObject *windowObject) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		[bridge injectValue:strongSelf forKey:@"Controller"];
		[strongSelf installJavaScriptBridgeHelpers];
	};

	self.bridge.didFinishLoadHandler = ^(PBWebViewBridge *bridge) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf->finishedLoading = YES;
		if ([strongSelf respondsToSelector:@selector(didLoad)])
			[strongSelf performSelector:@selector(didLoad)];
	};

	self.bridge.requestRewriter = ^NSURLRequest * (PBWebViewBridge *bridge, NSURLRequest *request) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.repository)
			return request;

		NSURL *url = request.URL;
		if (!url)
			return request;

		NSString *scheme = [[url scheme] lowercaseString];
		if ([scheme isEqualToString:@"gitx"]) {
			NSMutableURLRequest *newRequest = [request mutableCopy];
			[newRequest setRepository:strongSelf.repository];
			return newRequest;
		}

		return request;
	};

	PBWebViewBridgeNavigationHandler navigationBlock = ^BOOL (PBWebViewBridge *bridge, NSURLRequest *request) {
		NSURL *url = request.URL;
		if (!url) {
			return NO;
		}
		NSString *scheme = [[url scheme] lowercaseString];
		if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
			[[NSWorkspace sharedWorkspace] openURL:url];
			return YES;
		}
		return NO;
	};

	self.bridge.navigationHandler = navigationBlock;
	self.bridge.newWindowHandler = navigationBlock;

	self.bridge.contextMenuHandler = ^NSArray * (PBWebViewBridge *bridge, NSDictionary *element, NSArray *defaultMenuItems) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) {
			return defaultMenuItems;
		}
		SEL menuSelector = @selector(webView:contextMenuItemsForElement:defaultMenuItems:);
		if ([strongSelf respondsToSelector:menuSelector]) {
			return [(id)strongSelf webView:bridge.webView contextMenuItemsForElement:element defaultMenuItems:defaultMenuItems];
		}
		return defaultMenuItems;
	};

	[self.bridge loadStartFileNamed:startFile];
}

- (WebScriptObject *) script
{
	return [self.bridge windowScriptObject];
}

- (void)installJavaScriptBridgeHelpers
{
	static NSString *const kBridgeBootstrap =
	@"(function(){\n"
	 "  var gitx = window.gitx = window.gitx || {};\n"
	 "  gitx.postMessage = function(payload){\n"
	 "    try {\n"
	 "      Controller.postJSONMessage_(JSON.stringify(payload || {}));\n"
	 "    } catch (error) {\n"
	 "      if (window.console && console.error) { console.error('gitx.postMessage failed', error); }\n"
	 "    }\n"
	 "  };\n"
	 "})();";

	[self.bridge evaluateJavaScript:kBridgeBootstrap completion:nil];
}

- (void)closeView
{
	if (view) {
		[self.bridge removeValueForKey:@"Controller"];
		[view close];
	}

	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)postJSONMessage:(NSString *)jsonMessage
{
	if (![jsonMessage isKindOfClass:[NSString class]]) {
		return;
	}

	NSData *data = [jsonMessage dataUsingEncoding:NSUTF8StringEncoding];
	if (!data) {
		return;
	}

	NSError *error = nil;
	id payloadObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	if (!payloadObject || ![payloadObject isKindOfClass:[NSDictionary class]]) {
		if (error) {
			NSLog(@"PBWebController: Failed to decode bridge payload: %@", error);
		}
		return;
	}

	NSDictionary *payload = (NSDictionary *)payloadObject;
	NSString *type = payload[@"type"];
	if (![type isKindOfClass:[NSString class]]) {
		NSLog(@"PBWebController: Ignoring bridge payload without string type: %@", payload);
		return;
	}

	[self handleBridgeMessage:type payload:payload];
}

- (void)handleBridgeMessage:(NSString *)type payload:(NSDictionary *)payload
{
	NSLog(@"PBWebController: Unhandled bridge message %@ with payload %@", type, payload);
}

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector
{
	return NO;
}

+ (BOOL)isKeyExcludedFromWebScript:(const char *)name {
	return NO;
}

#pragma mark Functions to be used from JavaScript

- (void) log: (NSString*) logMessage
{
	NSLog(@"%@", logMessage);
}

- (BOOL) isReachable:(NSString *)hostname
{
    SCNetworkReachabilityRef target;
    SCNetworkConnectionFlags flags = 0;
    Boolean reachable;
    target = SCNetworkReachabilityCreateWithName(NULL, [hostname cStringUsingEncoding:NSASCIIStringEncoding]);
    reachable = SCNetworkReachabilityGetFlags(target, &flags);
	CFRelease(target);

	if (!reachable)
		return FALSE;

	// If a connection is required, then it's not reachable
	if (flags & (kSCNetworkFlagsConnectionRequired | kSCNetworkFlagsConnectionAutomatic | kSCNetworkFlagsInterventionRequired))
		return FALSE;

	return flags > 0;
}


#pragma mark Using async function from JS

- (void) runCommand:(WebScriptObject *)arguments inRepository:(PBGitRepository *)repo callBack:(WebScriptObject *)callBack
{
	// The JS bridge does not handle JS Arrays, even though the docs say it does. So, we convert it ourselves.
	NSInteger length = [[arguments valueForKey:@"length"] integerValue];
	NSMutableArray *realArguments = [NSMutableArray arrayWithCapacity:(NSUInteger)length];
	NSInteger i = 0;
	for (i = 0; i < length; i++)
		[realArguments addObject:[arguments webScriptValueAtIndex:(unsigned int)i]];

	NSFileHandle *handle = [repo handleInWorkDirForArguments:realArguments];
	[callbacks setObject:callBack forKey:handle];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(JSRunCommandDone:) name:NSFileHandleReadToEndOfFileCompletionNotification object:handle]; 
	[handle readToEndOfFileInBackgroundAndNotify];
}

- (void) returnCallBackForObject:(id)object withData:(id)data
{
	WebScriptObject *a = [callbacks objectForKey: object];
	if (!a) {
		NSLog(@"Could not find a callback for object: %@", object);
		return;
	}

	[callbacks removeObjectForKey:object];
	[a callWebScriptMethod:@"call" withArguments:[NSArray arrayWithObjects:@"", data, nil]];
}

- (void) threadFinished:(NSArray *)arguments
{
	[self returnCallBackForObject:[arguments objectAtIndex:0] withData:[arguments objectAtIndex:1]];
}

- (void) JSRunCommandDone:(NSNotification *)notification
{
	NSString *data = [[NSString alloc] initWithData:[[notification userInfo] valueForKey:NSFileHandleNotificationDataItem] encoding:NSUTF8StringEncoding];
	[self returnCallBackForObject:[notification object] withData:data];
}


@end
