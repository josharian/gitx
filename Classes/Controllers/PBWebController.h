//
//  PBWebController.h
//  GitX
//
//  Created by Pieter de Bie on 08-10-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class PBWebViewBridge;

@interface PBWebController : NSObject {
	IBOutlet WebView* view;
	NSString *startFile;
	BOOL finishedLoading;

	// For async git reading
	NSMapTable *callbacks;

	// For the repository access
	IBOutlet id repository;

	PBWebViewBridge *_bridge;
}

@property  NSString *startFile;
@property  id repository;

- (WebScriptObject *) script;
- (void) closeView;

- (void)handleBridgeMessage:(NSString *)type payload:(NSDictionary *)payload NS_REQUIRES_SUPER;
- (void)sendBridgeEventWithType:(NSString *)type payload:(NSDictionary *)payload;

@property (nonatomic, strong, readonly) PBWebViewBridge *bridge;
@end
