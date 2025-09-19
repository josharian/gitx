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
#import "PBWebBridge.h"
#import "PBWebViewBridge.h"
#import "PBWKWebViewBridge.h"
#import "PBWKGitXSchemeHandler.h"

@interface PBWebController ()
@property (nonatomic, strong) id<PBWebBridge> bridge;
@property (nonatomic, strong) NSView *webContentView;
@property (nonatomic, strong) PBWKGitXSchemeHandler *gitxSchemeHandler;
@property (nonatomic, strong) NSDictionary *lastContextMenuPayload;
- (void)installJavaScriptBridgeHelpersForBridge:(id<PBWebBridge>)bridge;
- (void)injectLegacyControllerIfNeededForBridge:(id<PBWebBridge>)bridge;
- (void)handleDecodedBridgePayload:(NSDictionary *)payload;
@end

static NSString * const PBWebControllerWebViewNativePostScript =
@"window.gitxNativePost = window.gitxNativePost || function(payload){\n"
 "  try {\n"
 "    Controller.postJSONMessage_(JSON.stringify(payload || {}));\n"
 "  } catch (error) {\n"
 "    if (window.console && console.error) { console.error('gitxNativePost failed', error); }\n"
 "  }\n"
 "};";

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

@synthesize startFile, repository, bridge = _bridge, webContentView = _webContentView;

- (void)awakeFromNib
{
	finishedLoading = NO;

	NSBundle *bundle = [NSBundle mainBundle];
	NSView *resolvedView = view;
	id<PBWebBridge> bridge = nil;
	__weak typeof(self) weakSelf = self;
	PBWKGitXSchemeHandler *schemeHandler = nil;

	if ([resolvedView isKindOfClass:[WKWebView class]]) {
		WKWebView *existingWebView = (WKWebView *)resolvedView;
		schemeHandler = [[PBWKGitXSchemeHandler alloc] initWithRepositoryProvider:^PBGitRepository * _Nullable{
			__strong typeof(weakSelf) strongSelf = weakSelf;
			return (PBGitRepository *)strongSelf.repository;
		}];
		@try {
			[existingWebView.configuration setURLSchemeHandler:schemeHandler forURLScheme:@"gitx"];
		} @catch (__unused NSException *exception) {
		}
		bridge = [[PBWKWebViewBridge alloc] initWithWebView:existingWebView bundle:bundle];
	} else if ([resolvedView isKindOfClass:[WebView class]]) {
		bridge = (id<PBWebBridge>)[[PBWebViewBridge alloc] initWithWebView:(WebView *)resolvedView bundle:bundle];
	} else {
		WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
		schemeHandler = [[PBWKGitXSchemeHandler alloc] initWithRepositoryProvider:^PBGitRepository * _Nullable{
			__strong typeof(weakSelf) strongSelf = weakSelf;
			return (PBGitRepository *)strongSelf.repository;
		}];
		[configuration setURLSchemeHandler:schemeHandler forURLScheme:@"gitx"];
		WKWebView *wkWebView = [[WKWebView alloc] initWithFrame:resolvedView.bounds configuration:configuration];
		wkWebView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		[resolvedView addSubview:wkWebView];
		resolvedView = wkWebView;
		bridge = [[PBWKWebViewBridge alloc] initWithWebView:wkWebView bundle:bundle];
	}

	self.gitxSchemeHandler = schemeHandler;

	self.webContentView = resolvedView;
	view = resolvedView;
	self.bridge = bridge;
	if (!self.bridge) {
		NSLog(@"PBWebController: Unable to initialize web bridge for view %@", resolvedView);
		return;
	}

	bridge.didClearWindowObjectHandler = ^(id<PBWebBridge> activeBridge, id windowObject) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf.lastContextMenuPayload = nil;
		[strongSelf injectLegacyControllerIfNeededForBridge:activeBridge];
		[strongSelf installJavaScriptBridgeHelpersForBridge:activeBridge];
	};

	bridge.didFinishLoadHandler = ^(id<PBWebBridge> activeBridge) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf->finishedLoading = YES;
		if ([strongSelf respondsToSelector:@selector(didLoad)]) {
			[strongSelf performSelector:@selector(didLoad)];
		}
	};

	bridge.requestRewriter = ^NSURLRequest * (id<PBWebBridge> activeBridge, NSURLRequest *request) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.repository) {
			return request;
		}

		if ([activeBridge isKindOfClass:[PBWKWebViewBridge class]]) {
			return request;
		}

		NSURL *url = request.URL;
		if (!url) {
			return request;
		}

		NSString *scheme = [[url scheme] lowercaseString];
		if ([scheme isEqualToString:@"gitx"]) {
			PBGitRepository *requestRepository = nil;
			@try {
				requestRepository = [request repository];
			} @catch (__unused NSException *exception) {
				requestRepository = nil;
			}

			if (requestRepository == strongSelf.repository) {
				return request;
			}

			NSMutableURLRequest *newRequest = [request mutableCopy];
			[newRequest setRepository:strongSelf.repository];
			return newRequest;
		}

		return request;
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
		if ([activeBridge isKindOfClass:[PBWKWebViewBridge class]]) {
			NSDictionary *stored = strongSelf.lastContextMenuPayload;
			if ([stored isKindOfClass:[NSDictionary class]]) {
				elementInfo = stored;
			}
			strongSelf.lastContextMenuPayload = nil;
		}

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

- (WebScriptObject *)script
{
	if ([self.bridge isKindOfClass:[PBWebViewBridge class]]) {
		return [(PBWebViewBridge *)self.bridge windowScriptObject];
	}
	return nil;
}

- (void)installJavaScriptBridgeHelpersForBridge:(id<PBWebBridge>)bridge
{
	if (!bridge) {
		return;
	}

	NSString *nativePostScript = [bridge isKindOfClass:[PBWebViewBridge class]] ? PBWebControllerWebViewNativePostScript : PBWebControllerWKNativePostScript;
	void (^ignoreResult)(id, NSError *) = ^(id __unused result, NSError *__unused error) {};
	[bridge evaluateJavaScript:nativePostScript completion:ignoreResult];
	[bridge evaluateJavaScript:PBWebControllerBridgeBootstrapScript completion:ignoreResult];
	[bridge evaluateJavaScript:PBWebControllerContextMenuTrackingScript completion:ignoreResult];
}

- (void)injectLegacyControllerIfNeededForBridge:(id<PBWebBridge>)bridge
{
	if (![bridge isKindOfClass:[PBWebViewBridge class]]) {
		return;
	}

	PBWebViewBridge *webBridge = (PBWebViewBridge *)bridge;
	[webBridge injectValue:self forKey:@"Controller"];
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

	NSError *jsonError = nil;
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:message options:0 error:&jsonError];
	if (!jsonData) {
		NSLog(@"PBWebController: Failed to encode bridge message %@: %@", type, jsonError);
		return;
	}

	NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
	if (!jsonString) {
		NSLog(@"PBWebController: Failed to build JSON string for message %@", type);
		return;
	}

	__weak typeof(self) weakSelf = self;
	[self.bridge sendJSONMessageString:jsonString completion:^(NSError * _Nullable error) {
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
	if ([self.bridge isKindOfClass:[PBWebViewBridge class]]) {
		PBWebViewBridge *webBridge = (PBWebViewBridge *)self.bridge;
		[webBridge removeValueForKey:@"Controller"];
	}

	NSView *contentView = self.webContentView ?: view;
	if ([contentView respondsToSelector:@selector(close)]) {
		[(id)contentView close];
	} else if ([contentView isKindOfClass:[WKWebView class]]) {
		[(WKWebView *)contentView stopLoading];
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

	[self handleDecodedBridgePayload:(NSDictionary *)payloadObject];
}

- (void)handleBridgeMessage:(NSString *)type payload:(NSDictionary *)payload
{
	NSLog(@"PBWebController: Unhandled bridge message %@ with payload %@", type, payload);
}

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector
{
	return aSelector != @selector(postJSONMessage:);
}

@end
