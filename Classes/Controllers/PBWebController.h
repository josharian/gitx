//
//  PBWebController.h
//  GitX
//
//  Created by Pieter de Bie on 08-10-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PBWebBridge;
@class PBWKWebViewBridge;
@class PBWKGitXSchemeHandler;

@interface PBWebController : NSObject {
	IBOutlet NSView *view;
	NSString * _Nullable startFile;
	BOOL finishedLoading;

    // For the repository access
    IBOutlet id _Nullable repository;

	id<PBWebBridge> _Nullable _bridge;
}

@property (copy, nullable) NSString *startFile;
@property (strong, nullable) id repository;

- (void) closeView;

- (void)handleBridgeMessage:(NSString *)type payload:(nullable NSDictionary *)payload NS_REQUIRES_SUPER;
- (void)sendBridgeEventWithType:(NSString *)type payload:(NSDictionary *)payload;

@property (nonatomic, strong, readonly, nullable) id<PBWebBridge> bridge;
@property (nonatomic, strong, readonly, nullable) WKWebView *webView;

- (nullable NSArray *)contextMenuItemsForBridge:(id<PBWebBridge>)bridge
                                    elementInfo:(nullable NSDictionary *)elementInfo
                              defaultMenuItems:(NSArray *)defaultMenuItems;
@end

NS_ASSUME_NONNULL_END
