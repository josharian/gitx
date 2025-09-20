//
//  PBWebController.m
//  GitX
//
//  Created by Pieter de Bie on 08-10-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBWebController.h"
#import "PBGitRepository.h"
#import "PBWebBridge.h"
#import "PBWKWebViewBridge.h"
#import "PBWKGitXSchemeHandler.h"

@interface PBWebController ()
@property (nonatomic, strong) id<PBWebBridge> bridge;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) PBWKGitXSchemeHandler *gitxSchemeHandler;
@property (nonatomic, strong) NSDictionary *lastContextMenuPayload;
@property (nonatomic, assign) BOOL bridgeUserScriptsInstalled;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *pendingBridgeMessages;
- (void)configureBridgeUserScriptsIfNeeded;
- (void)handleDecodedBridgePayload:(NSDictionary *)payload;
- (void)flushPendingBridgeMessages;
- (void)dispatchBridgeMessage:(NSDictionary *)message;
- (NSArray<NSString *> *)bridgeUserScriptResourceNames;
- (NSString *)bridgeUserScriptSourceNamed:(NSString *)resourceName;
@end

@implementation PBWebController

@synthesize startFile, repository, bridge = _bridge, webView = _webView;


- (void)awakeFromNib
{
	finishedLoading = NO;
	self.pendingBridgeMessages = [NSMutableArray array];

	NSBundle *bundle = [NSBundle mainBundle];
	NSView *containerView = view;
	__weak typeof(self) weakSelf = self;

	WKWebView *previousWebView = self.webView;
	WKWebView *resolvedWebView = nil;
	WKWebViewConfiguration *configuration = nil;
	if ([containerView isKindOfClass:[WKWebView class]]) {
		resolvedWebView = (WKWebView *)containerView;
		configuration = resolvedWebView.configuration;
	} else {
		configuration = [[WKWebViewConfiguration alloc] init];
		configuration.processPool = [[WKProcessPool alloc] init];
		resolvedWebView = [[WKWebView alloc] initWithFrame:containerView.bounds configuration:configuration];
		resolvedWebView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		[containerView addSubview:resolvedWebView];
	}

	self.webView = resolvedWebView;
	if (previousWebView != resolvedWebView) {
		self.bridgeUserScriptsInstalled = NO;
	}
	[self configureBridgeUserScriptsIfNeeded];

	id existingHandler = nil;
	if ([configuration respondsToSelector:@selector(urlSchemeHandlerForURLScheme:)]) {
		existingHandler = [configuration urlSchemeHandlerForURLScheme:@"gitx"];
	}

	PBWKGitXSchemeHandler *schemeHandler = nil;
	if ([existingHandler isKindOfClass:[PBWKGitXSchemeHandler class]]) {
		schemeHandler = (PBWKGitXSchemeHandler *)existingHandler;
		[schemeHandler updateRepositoryProvider:^PBGitRepository * _Nullable{
			__strong typeof(weakSelf) strongSelf = weakSelf;
			return (PBGitRepository *)strongSelf.repository;
		}];
	} else {
		schemeHandler = [[PBWKGitXSchemeHandler alloc] initWithRepositoryProvider:^PBGitRepository * _Nullable{
			__strong typeof(weakSelf) strongSelf = weakSelf;
			return (PBGitRepository *)strongSelf.repository;
		}];
		if ([configuration respondsToSelector:@selector(setURLSchemeHandler:forURLScheme:)]) {
			@try {
				[configuration setURLSchemeHandler:schemeHandler forURLScheme:@"gitx"];
			} @catch (NSException *exception) {
				NSLog(@"PBWebController: Failed to register gitx scheme handler: %@", exception);
			}
		}
	}
	self.gitxSchemeHandler = schemeHandler;

	id<PBWebBridge> bridge = [[PBWKWebViewBridge alloc] initWithWebView:resolvedWebView bundle:bundle];
	self.bridge = bridge;
	if (!self.bridge) {
		NSLog(@"PBWebController: Unable to initialize web bridge for view %@", resolvedWebView);
		return;
	}

	bridge.didClearWindowObjectHandler = ^(id<PBWebBridge> activeBridge, id  _Nullable windowObject) {
		#pragma unused(activeBridge, windowObject)
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf.lastContextMenuPayload = nil;
	};

	bridge.didFinishLoadHandler = ^(id<PBWebBridge> activeBridge) {
		#pragma unused(activeBridge)
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf->finishedLoading = YES;
		if ([strongSelf respondsToSelector:@selector(didLoad)]) {
			[strongSelf performSelector:@selector(didLoad)];
		}
		[strongSelf flushPendingBridgeMessages];
	};

	PBWebBridgeNavigationHandler navigationBlock = ^BOOL (id<PBWebBridge> activeBridge, NSURLRequest *request) {
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

	bridge.navigationHandler = navigationBlock;
	bridge.newWindowHandler = navigationBlock;

	bridge.contextMenuHandler = ^NSArray * (id<PBWebBridge> activeBridge, NSDictionary *element, NSArray *defaultMenuItems) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) {
			return defaultMenuItems;
		}

		NSDictionary *elementInfo = element ?: @{};
		NSDictionary *stored = strongSelf.lastContextMenuPayload;
		if ([stored isKindOfClass:[NSDictionary class]]) {
			elementInfo = stored;
		}
		strongSelf.lastContextMenuPayload = nil;

		NSArray *items = [strongSelf contextMenuItemsForBridge:activeBridge elementInfo:elementInfo defaultMenuItems:defaultMenuItems];
		return items ?: defaultMenuItems;
	};

	bridge.jsonMessageHandler = ^(id<PBWebBridge> activeBridge, NSDictionary *payload) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		[strongSelf handleDecodedBridgePayload:payload];
	};

	[bridge loadStartFileNamed:startFile];
}

- (void)configureBridgeUserScriptsIfNeeded
{
	if (self.bridgeUserScriptsInstalled) {
		return;
	}

	WKWebView *activeWebView = self.webView;
	if (!activeWebView) {
		return;
	}

	WKUserContentController *contentController = activeWebView.configuration.userContentController;
	if (!contentController) {
		return;
	}

	for (NSString *resourceName in [self bridgeUserScriptResourceNames]) {
		NSString *source = [self bridgeUserScriptSourceNamed:resourceName];
		if (source.length == 0) {
			continue;
		}
		WKUserScript *script = [[WKUserScript alloc] initWithSource:source
						injectionTime:WKUserScriptInjectionTimeAtDocumentStart
				 forMainFrameOnly:NO];
		[contentController addUserScript:script];
	}

	self.bridgeUserScriptsInstalled = YES;
}

- (void)handleDecodedBridgePayload:(NSDictionary *)payload
{
	if (![payload isKindOfClass:[NSDictionary class]]) {
		return;
	}

	NSString *type = payload[@"type"];
	if (![type isKindOfClass:[NSString class]]) {
		NSLog(@"PBWebController: Ignoring bridge payload without string type: %@", payload);
		return;
	}

	if ([type isEqualToString:@"__contextMenuPreview__"]) {
		id info = payload[@"info"];
		if ([info isKindOfClass:[NSDictionary class]]) {
			self.lastContextMenuPayload = info;
		}
		return;
	}

	[self handleBridgeMessage:type payload:payload];
}

- (NSArray *)contextMenuItemsForBridge:(id<PBWebBridge>)bridge elementInfo:(NSDictionary *)elementInfo defaultMenuItems:(NSArray *)defaultMenuItems
{
	#pragma unused(bridge, elementInfo)
	return defaultMenuItems;
}

- (void)sendBridgeEventWithType:(NSString *)type payload:(NSDictionary *)payload
{
	if (type.length == 0)
		return;

	NSMutableDictionary *message = [NSMutableDictionary dictionary];
	message[@"type"] = type;
	if (payload.count)
		[message addEntriesFromDictionary:payload];

	if (![NSJSONSerialization isValidJSONObject:message]) {
		NSLog(@"PBWebController: Bridge message for type %@ is not JSON serializable: %@", type, message);
		return;
	}

	if (!finishedLoading) {
		if (!self.pendingBridgeMessages) {
			self.pendingBridgeMessages = [NSMutableArray array];
		}
		[self.pendingBridgeMessages addObject:[message copy]];
		return;
	}

	[self dispatchBridgeMessage:message];
}

- (void)closeView
{
	[self.webView stopLoading];
	self.bridge = nil;
	self.gitxSchemeHandler = nil;
	self.lastContextMenuPayload = nil;
	[self.pendingBridgeMessages removeAllObjects];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleBridgeMessage:(NSString *)type payload:(NSDictionary *)payload
{
	NSLog(@"PBWebController: Unhandled bridge message %@ with payload %@", type, payload);
}

- (void)flushPendingBridgeMessages
{
	if (!finishedLoading || self.pendingBridgeMessages.count == 0)
		return;

	NSArray<NSDictionary *> *queuedMessages = [self.pendingBridgeMessages copy];
	[self.pendingBridgeMessages removeAllObjects];
	for (NSDictionary *message in queuedMessages) {
		[self dispatchBridgeMessage:message];
	}
}

- (void)dispatchBridgeMessage:(NSDictionary *)message
{
	if (!message || !self.bridge)
		return;

	__weak typeof(self) weakSelf = self;
	[self.bridge sendJSONMessage:message completion:^(NSError * _Nullable error) {
		if (!error)
			return;
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf)
			return;
		NSString *type = [message objectForKey:@"type"];
		NSLog(@"PBWebController: Failed to dispatch message %@: %@", type, error);
	}];
}

- (NSArray<NSString *> *)bridgeUserScriptResourceNames
{
	return @[ @"PBWebControllerNativePost",
		@"PBWebControllerBridgeBootstrap",
		@"PBWebControllerContextMenuTracking" ];
}

- (NSString *)bridgeUserScriptSourceNamed:(NSString *)resourceName
{
	if (resourceName.length == 0)
		return nil;

	NSBundle *bundle = [NSBundle mainBundle];
	NSURL *resourceURL = [bundle URLForResource:resourceName withExtension:@"js"];
	if (!resourceURL) {
		NSLog(@"PBWebController: Missing bridge script resource %@.js", resourceName);
		return nil;
	}

	NSError *error = nil;
	NSString *source = [NSString stringWithContentsOfURL:resourceURL encoding:NSUTF8StringEncoding error:&error];
	if (!source) {
		NSLog(@"PBWebController: Failed to load bridge script %@.js: %@", resourceName, error);
	}
	return source;
}

@end
