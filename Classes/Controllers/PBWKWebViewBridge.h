//
//  PBWKWebViewBridge.h
//  GitX
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "PBWebBridge.h"

NS_ASSUME_NONNULL_BEGIN

@interface PBWKWebViewBridge : NSObject <PBWebBridge, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler>

@property (nonatomic, strong, readonly) WKWebView *webView;
@property (nonatomic, strong, readonly) NSBundle *bundle;
@property (nonatomic, copy, nullable) PBWebBridgeLoadHandler didFinishLoadHandler;
@property (nonatomic, copy, nullable) PBWebBridgeWindowObjectHandler didClearWindowObjectHandler;
@property (nonatomic, copy, nullable) PBWebBridgeRequestRewriter requestRewriter;
@property (nonatomic, copy, nullable) PBWebBridgeNavigationHandler navigationHandler;
@property (nonatomic, copy, nullable) PBWebBridgeNavigationHandler newWindowHandler;
@property (nonatomic, copy, nullable) PBWebBridgeContextMenuHandler contextMenuHandler;
@property (nonatomic, copy, nullable) PBWebBridgeJSONMessageHandler jsonMessageHandler;

- (instancetype)initWithWebView:(WKWebView *)webView bundle:(NSBundle *)bundle NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
