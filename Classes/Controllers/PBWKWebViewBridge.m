//
//  PBWKWebViewBridge.m
//  GitX
//
//  Created by ChatGPT on 2024-XX-XX.
//

#import "PBWKWebViewBridge.h"

static NSString * const PBWKWebViewBridgeErrorDomain = @"PBWKWebViewBridgeErrorDomain";
static NSString * const PBWKWebViewBridgeMessageHandlerName = @"gitxBridge";

@interface PBWKWebViewBridge ()
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSBundle *bundle;
@end

@implementation PBWKWebViewBridge

- (instancetype)initWithWebView:(WKWebView *)webView bundle:(NSBundle *)bundle
{
    NSParameterAssert(webView);

    self = [super init];
    if (!self) {
        return nil;
    }

    _webView = webView;
    _bundle = bundle ?: [NSBundle mainBundle];

    _webView.navigationDelegate = self;
    _webView.UIDelegate = self;

    WKUserContentController *contentController = _webView.configuration.userContentController;
    [contentController addScriptMessageHandler:self name:PBWKWebViewBridgeMessageHandlerName];

    return self;
}

- (void)dealloc
{
    WKUserContentController *contentController = self.webView.configuration.userContentController;
    [contentController removeScriptMessageHandlerForName:PBWKWebViewBridgeMessageHandlerName];
    self.webView.navigationDelegate = nil;
    self.webView.UIDelegate = nil;
}

#pragma mark - PBWebBridge

- (NSView *)view
{
    return self.webView;
}

- (void)loadStartFileNamed:(NSString *)startFile
{
    if (startFile.length == 0) {
        return;
    }

    NSString *directoryPath = [NSString stringWithFormat:@"html/views/%@", startFile];
    NSString *filePath = [self.bundle pathForResource:@"index" ofType:@"html" inDirectory:directoryPath];
    if (!filePath) {
        NSLog(@"PBWKWebViewBridge: Failed to resolve start file %@", startFile);
        return;
    }

    NSURL *fileURL = [NSURL fileURLWithPath:filePath isDirectory:NO];
    NSURL *readAccessURL = [fileURL URLByDeletingLastPathComponent];
    if (!readAccessURL) {
        readAccessURL = [fileURL URLByDeletingLastPathComponent];
    }

    [self.webView loadFileURL:fileURL allowingReadAccessToURL:readAccessURL];
}

- (void)evaluateJavaScript:(NSString *)javascript completion:(void (^)(id _Nullable, NSError * _Nullable))completion
{
    if (!javascript.length) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:PBWKWebViewBridgeErrorDomain
                                                 code:1
                                             userInfo:@{ NSLocalizedDescriptionKey: @"Cannot evaluate empty JavaScript" }];
            completion(nil, error);
        }
        return;
    }

    [self.webView evaluateJavaScript:javascript
                    completionHandler:^(id _Nullable result, NSError * _Nullable error) {
                        if (completion) {
                            completion(result, error);
                        }
                    }];
}

- (void)sendJSONMessageString:(NSString *)jsonString completion:(void (^)(NSError * _Nullable))completion
{
    if (jsonString.length == 0) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:PBWKWebViewBridgeErrorDomain
                                                 code:2
                                             userInfo:@{ NSLocalizedDescriptionKey: @"Cannot send empty bridge message" }];
            completion(error);
        }
        return;
    }

    NSError *encodingError = nil;
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:@[jsonString]
                                                      options:0
                                                        error:&encodingError];
    if (!encoded) {
        if (completion) {
            completion(encodingError);
        }
        return;
    }

    NSString *arrayLiteral = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
    if (arrayLiteral.length < 2) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:PBWKWebViewBridgeErrorDomain
                                                 code:3
                                             userInfo:@{ NSLocalizedDescriptionKey: @"Failed to encode bridge message" }];
            completion(error);
        }
        return;
    }

    NSString *stringLiteral = [arrayLiteral substringWithRange:NSMakeRange(1, arrayLiteral.length - 2)];
    NSString *script = [NSString stringWithFormat:@"window.gitxReceiveNativeMessage(%@);", stringLiteral];

    [self evaluateJavaScript:script
                   completion:^(id  _Nullable __unused result, NSError * _Nullable error) {
                       if (completion) {
                           completion(error);
                       }
                   }];
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    id body = message.body;
    NSDictionary *payload = nil;

    if ([body isKindOfClass:[NSDictionary class]]) {
        payload = body;
    } else if ([body isKindOfClass:[NSString class]]) {
        NSData *data = [(NSString *)body dataUsingEncoding:NSUTF8StringEncoding];
        if (data) {
            NSError *error = nil;
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if (!error && [object isKindOfClass:[NSDictionary class]]) {
                payload = object;
            } else if (error) {
                NSLog(@"PBWKWebViewBridge: Failed to decode script message: %@", error);
            }
        }
    } else {
        NSLog(@"PBWKWebViewBridge: Ignoring unsupported script message body: %@", body);
    }

    if (payload && self.jsonMessageHandler) {
        self.jsonMessageHandler(self, payload);
    }
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURLRequest *request = navigationAction.request;
    if (self.requestRewriter) {
        NSURLRequest *rewritten = self.requestRewriter(self, request);
        if (rewritten && rewritten != request) {
            decisionHandler(WKNavigationActionPolicyCancel);
            [webView loadRequest:rewritten];
            return;
        }
    }

    BOOL handledExternally = NO;

    if (self.navigationHandler) {
        handledExternally = self.navigationHandler(self, request);
    }

    if (handledExternally) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler
{
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    if (self.didClearWindowObjectHandler) {
        self.didClearWindowObjectHandler(self, nil);
    }

    if (self.didFinishLoadHandler) {
        self.didFinishLoadHandler(self);
    }
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures
{
    NSURLRequest *request = navigationAction.request;
    BOOL handled = NO;

    if (self.newWindowHandler) {
        handled = self.newWindowHandler(self, request);
    }

    if (!handled && self.navigationHandler) {
        handled = self.navigationHandler(self, request);
    }

    if (handled) {
        return nil;
    }

    return [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
}

#pragma mark - WKUIDelegate (Context Menu)

- (void)webView:(WKWebView *)webView contextMenuWillPresentMenu:(NSMenu *)menu
{
    if (!self.contextMenuHandler || menu.itemArray.count == 0) {
        return;
    }

    NSArray *customItems = self.contextMenuHandler(self, @{}, menu.itemArray);
    if (!customItems) {
        return;
    }

    [menu removeAllItems];
    for (NSMenuItem *item in customItems) {
        [menu addItem:item];
    }
}

@end
