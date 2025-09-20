//
//  PBWebBridge.h
//  GitX
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PBWebBridge;

typedef void (^PBWebBridgeLoadHandler)(id<PBWebBridge> bridge);
typedef void (^PBWebBridgeWindowObjectHandler)(id<PBWebBridge> bridge, id _Nullable windowObject);
typedef NSURLRequest * _Nullable (^PBWebBridgeRequestRewriter)(id<PBWebBridge> bridge, NSURLRequest *request);
typedef BOOL (^PBWebBridgeNavigationHandler)(id<PBWebBridge> bridge, NSURLRequest *request);
typedef NSArray * _Nullable (^PBWebBridgeContextMenuHandler)(id<PBWebBridge> bridge, NSDictionary *elementInfo, NSArray *defaultMenuItems);
typedef void (^PBWebBridgeJSONMessageHandler)(id<PBWebBridge> bridge, NSDictionary *payload);

@protocol PBWebBridge <NSObject>

@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, copy, nullable) PBWebBridgeLoadHandler didFinishLoadHandler;
@property (nonatomic, copy, nullable) PBWebBridgeWindowObjectHandler didClearWindowObjectHandler;
@property (nonatomic, copy, nullable) PBWebBridgeRequestRewriter requestRewriter;
@property (nonatomic, copy, nullable) PBWebBridgeNavigationHandler navigationHandler;
@property (nonatomic, copy, nullable) PBWebBridgeNavigationHandler newWindowHandler;
@property (nonatomic, copy, nullable) PBWebBridgeContextMenuHandler contextMenuHandler;
@property (nonatomic, copy, nullable) PBWebBridgeJSONMessageHandler jsonMessageHandler;

- (void)loadStartFileNamed:(NSString *)startFile;
- (void)evaluateJavaScript:(NSString *)javascript completion:(void (^)(id _Nullable result, NSError * _Nullable error))completion;
- (void)sendJSONMessage:(NSDictionary *)message completion:(void (^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
