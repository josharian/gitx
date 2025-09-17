//
//  PBWebViewBridge.h
//  GitX
//
//  Created by ChatGPT on 2024-XX-XX.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PBWebViewBridge;

typedef void (^PBWebViewBridgeLoadHandler)(PBWebViewBridge *bridge);
typedef void (^PBWebViewBridgeScriptHandler)(PBWebViewBridge *bridge, WebScriptObject *scriptObject);
typedef NSURLRequest * _Nullable (^PBWebViewBridgeRequestRewriter)(PBWebViewBridge *bridge, NSURLRequest *request);
typedef BOOL (^PBWebViewBridgeNavigationHandler)(PBWebViewBridge *bridge, NSURLRequest *request);
typedef BOOL (^PBWebViewBridgeNewWindowHandler)(PBWebViewBridge *bridge, NSURLRequest *request);
typedef NSArray * _Nullable (^PBWebViewBridgeContextMenuHandler)(PBWebViewBridge *bridge, NSDictionary *elementInfo, NSArray *defaultMenuItems);

@interface PBWebViewBridge : NSObject <WebFrameLoadDelegate, WebUIDelegate, WebPolicyDelegate, WebResourceLoadDelegate>

@property (nonatomic, weak, readonly) WebView *webView;
@property (nonatomic, strong, readonly) NSBundle *bundle;
@property (nonatomic, copy, nullable) PBWebViewBridgeLoadHandler didFinishLoadHandler;
@property (nonatomic, copy, nullable) PBWebViewBridgeScriptHandler didClearWindowObjectHandler;
@property (nonatomic, copy, nullable) PBWebViewBridgeRequestRewriter requestRewriter;
@property (nonatomic, copy, nullable) PBWebViewBridgeNavigationHandler navigationHandler;
@property (nonatomic, copy, nullable) PBWebViewBridgeNewWindowHandler newWindowHandler;
@property (nonatomic, copy, nullable) PBWebViewBridgeContextMenuHandler contextMenuHandler;

- (instancetype)initWithWebView:(WebView *)webView bundle:(NSBundle *)bundle;

- (void)loadStartFileNamed:(NSString *)startFile;
- (WebScriptObject *)windowScriptObject;
- (void)injectValue:(id)value forKey:(NSString *)key;
- (void)removeValueForKey:(NSString *)key;
- (id)callWebScriptMethod:(NSString *)method withArguments:(NSArray *)arguments;
- (void)evaluateJavaScript:(NSString *)javascript completion:(void (^)(id _Nullable result, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
