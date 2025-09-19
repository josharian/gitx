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
- (void)configureBridgeUserScriptsIfNeeded;
- (void)handleDecodedBridgePayload:(NSDictionary *)payload;
@end

static NSString * const PBWebControllerWKNativePostScript =
@"window.gitxNativePost = window.gitxNativePost || function(payload){\n"
 "  try {\n"
 "    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.gitxBridge) {\n"
 "      window.webkit.messageHandlers.gitxBridge.postMessage(payload || {});\n"
 "    }\n"
 "  } catch (error) {\n"
 "    if (window.console && console.error) { console.error('gitxNativePost failed', error); }\n"
 "  }\n"
 "};";

static NSString * const PBWebControllerBridgeBootstrapScript =
@"(function(){\n"
 "  var gitx = window.gitx = window.gitx || {};\n"
 "  gitx._nativeSubscribers = gitx._nativeSubscribers || [];\n"
 "  gitx.postMessage = gitx.postMessage || function(payload){\n"
 "    try { window.gitxNativePost(payload || {}); }\n"
 "    catch (error) { if (window.console && console.error) { console.error('gitx.postMessage failed', error); } }\n"
 "  };\n"
 "  gitx.subscribeToNativeMessages = gitx.subscribeToNativeMessages || function(handler){\n"
 "    if (typeof handler !== 'function') { return function(){}; }\n"
 "    gitx._nativeSubscribers.push(handler);\n"
 "    return function(){\n"
 "      var index = gitx._nativeSubscribers.indexOf(handler);\n"
 "      if (index >= 0) { gitx._nativeSubscribers.splice(index, 1); }\n"
 "    };\n"
 "  };\n"
 "  gitx._dispatchNativeMessage = function(message){\n"
 "    var payload = message;\n"
 "    if (typeof message === 'string') {\n"
 "      try { payload = JSON.parse(message); }\n"
 "      catch (error) {\n"
 "        if (window.console && console.error) { console.error('gitx._dispatchNativeMessage parse failure', error, message); }\n"
 "        return;\n"
 "      }\n"
 "    }\n"
 "    if (!payload || typeof payload !== 'object') {\n"
 "      return;\n"
 "    }\n"
 "    if (typeof gitx.onNativeMessage === 'function') {\n"
 "      try { gitx.onNativeMessage(payload); }\n"
 "      catch (error) { if (window.console && console.error) { console.error('gitx.onNativeMessage failure', error); } }\n"
 "    }\n"
 "    gitx._nativeSubscribers.slice().forEach(function(handler){\n"
 "      try { handler(payload); }\n"
 "      catch (error) { if (window.console && console.error) { console.error('gitx native subscriber failure', error); } }\n"
 "    });\n"
 "  };\n"
 "  window.gitxReceiveNativeMessage = gitx._dispatchNativeMessage;\n"
 "  if (window.gitxBridge && typeof window.gitxBridge.flush === 'function') {\n"
 "    try { window.gitxBridge.flush(); }\n"
 "    catch (error) { if (window.console && console.error) { console.error('gitxBridge.flush failed', error); } }\n"
 "  }\n"
 "})();";

static NSString * const PBWebControllerContextMenuTrackingScript =
@"(function(){\n"
 "  var gitx = window.gitx = window.gitx || {};\n"
 "  gitx._lastContextMenuInfo = gitx._lastContextMenuInfo || {};\n"
 "  gitx.getLastContextMenuInfo = function(){ return gitx._lastContextMenuInfo || {}; };\n"
 "  function extractInfo(target){\n"
 "    var info = { type: 'default' };\n"
 "    var node = target;\n"
 "    while (node) {\n"
 "      if (!info.refText && node.className && typeof node.className === 'string' && node.className.indexOf('refs ') === 0) {\n"
 "        info.type = 'refs';\n"
 "        info.refText = (node.textContent || '').trim();\n"
 "        break;\n"
 "      }\n"
 "      if (node.hasAttribute && node.hasAttribute('representedFile')) {\n"
 "        info.type = 'representedFile';\n"
 "        info.representedFile = node.getAttribute('representedFile') || '1';\n"
 "        break;\n"
 "      }\n"
 "      if (node.tagName && node.tagName.toUpperCase() === 'IMG') {\n"
 "        info.type = 'image';\n"
 "        break;\n"
 "      }\n"
 "      node = node.parentNode;\n"
 "    }\n"
 "    return info;\n"
 "  }\n"
 "  function handleContextMenu(event){\n"
 "    try {\n"
 "      var info = extractInfo(event.target || event.srcElement);\n"
 "      gitx._lastContextMenuInfo = info;\n"
 "      if (gitx.postMessage) {\n"
 "        gitx.postMessage({ type: '__contextMenuPreview__', info: info });\n"
 "      }\n"
 "    } catch (error) {\n"
 "      if (window.console && console.error) { console.error('gitx context menu tracking failed', error); }\n"
 "    }\n"
 "  }\n"
 "  if (document && document.addEventListener) {\n"
 "    document.addEventListener('contextmenu', handleContextMenu, true);\n"
 "  }\n"
 "})();";

@implementation PBWebController

@synthesize startFile, repository, bridge = _bridge, webView = _webView;


- (void)awakeFromNib
{
	finishedLoading = NO;

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

	NSArray<NSString *> *scriptSources = @[ PBWebControllerWKNativePostScript,
		PBWebControllerBridgeBootstrapScript,
		PBWebControllerContextMenuTrackingScript ];
	for (NSString *source in scriptSources) {
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

	__weak typeof(self) weakSelf = self;
	[self.bridge sendJSONMessage:message completion:^(NSError * _Nullable error) {
		if (!error) {
			return;
		}
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		NSLog(@"PBWebController: Failed to dispatch message %@: %@", type, error);
	}];
}

- (void)closeView
{
	[self.webView stopLoading];
	self.bridge = nil;
	self.gitxSchemeHandler = nil;
	self.lastContextMenuPayload = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleBridgeMessage:(NSString *)type payload:(NSDictionary *)payload
{
	NSLog(@"PBWebController: Unhandled bridge message %@ with payload %@", type, payload);
}

@end
