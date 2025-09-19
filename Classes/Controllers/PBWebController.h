//
//  PBWebController.h
//  GitX
//
//  Created by Pieter de Bie on 08-10-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@protocol PBWebBridge;
@class PBWKWebViewBridge;
@class PBWKGitXSchemeHandler;

@interface PBWebController : NSObject {
	IBOutlet NSView *view;
	NSString *startFile;
	BOOL finishedLoading;

	// For the repository access
	IBOutlet id repository;

	id<PBWebBridge> _bridge;
}

@property  NSString *startFile;
@property  id repository;

- (void) closeView;

- (void)handleBridgeMessage:(NSString *)type payload:(NSDictionary *)payload NS_REQUIRES_SUPER;
- (void)sendBridgeEventWithType:(NSString *)type payload:(NSDictionary *)payload;

@property (nonatomic, strong, readonly) id<PBWebBridge> bridge;
@property (nonatomic, strong, readonly) WKWebView *webView;

- (NSArray *)contextMenuItemsForBridge:(id<PBWebBridge>)bridge
                            elementInfo:(NSDictionary *)elementInfo
                      defaultMenuItems:(NSArray *)defaultMenuItems;
@end
