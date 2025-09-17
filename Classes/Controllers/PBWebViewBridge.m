//
//  PBWebViewBridge.m
//  GitX
//
//  Created by ChatGPT on 2024-XX-XX.
//

#import "PBWebViewBridge.h"

static NSString * const PBWebViewBridgeErrorDomain = @"PBWebViewBridgeErrorDomain";

@interface PBWebViewBridge ()
@property (nonatomic, weak) WebView *webView;
@property (nonatomic, strong) NSBundle *bundle;
@end

@implementation PBWebViewBridge

- (instancetype)initWithWebView:(WebView *)webView bundle:(NSBundle *)bundle
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _webView = webView;
    _bundle = bundle ?: [NSBundle mainBundle];

    _webView.UIDelegate = self;
    _webView.frameLoadDelegate = self;
    _webView.policyDelegate = self;
    _webView.resourceLoadDelegate = self;

    return self;
}

- (void)loadStartFileNamed:(NSString *)startFile
{
    if (!startFile.length) {
        return;
    }

    NSString *path = [NSString stringWithFormat:@"html/views/%@", startFile];
    NSString *file = [self.bundle pathForResource:@"index" ofType:@"html" inDirectory:path];
    if (!file) {
        NSLog(@"PBWebViewBridge: Failed to resolve start file %@", startFile);
        return;
    }

    NSURL *url = [NSURL fileURLWithPath:file];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [[self.webView mainFrame] loadRequest:request];
}

- (WebScriptObject *)windowScriptObject
{
    return [self.webView windowScriptObject];
}

- (void)injectValue:(id)value forKey:(NSString *)key
{
    if (!key.length) {
        return;
    }

    [[self windowScriptObject] setValue:value forKey:key];
}

- (void)removeValueForKey:(NSString *)key
{
    if (!key.length) {
        return;
    }

    [[self windowScriptObject] setValue:nil forKey:key];
}

- (id)callWebScriptMethod:(NSString *)method withArguments:(NSArray *)arguments
{
    return [[self windowScriptObject] callWebScriptMethod:method withArguments:arguments];
}

- (void)evaluateJavaScript:(NSString *)javascript completion:(void (^)(id _Nullable, NSError * _Nullable))completion
{
    if (!completion) {
        (void)[self.webView stringByEvaluatingJavaScriptFromString:javascript];
        return;
    }

    if (!javascript.length) {
        NSError *error = [NSError errorWithDomain:PBWebViewBridgeErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Cannot evaluate empty JavaScript"}];
        completion(nil, error);
        return;
    }

    NSString *result = [self.webView stringByEvaluatingJavaScriptFromString:javascript];
    completion(result, nil);
}

#pragma mark - WebFrameLoadDelegate

- (void)webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)windowObject forFrame:(WebFrame *)frame
{
    if (self.didClearWindowObjectHandler) {
        self.didClearWindowObjectHandler(self, windowObject);
    }
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    if (self.didFinishLoadHandler) {
        self.didFinishLoadHandler(self);
    }
}

#pragma mark - WebResourceLoadDelegate

- (NSURLRequest *)webView:(WebView *)sender
                 resource:(id)identifier
          willSendRequest:(NSURLRequest *)request
         redirectResponse:(NSURLResponse *)redirectResponse
           fromDataSource:(WebDataSource *)dataSource
{
    if (self.requestRewriter) {
        NSURLRequest *rewritten = self.requestRewriter(self, request);
        if (rewritten) {
            return rewritten;
        }
    }
    return request;
}

#pragma mark - WebPolicyDelegate

- (void)webView:(WebView *)webView
        decidePolicyForNavigationAction:(NSDictionary *)actionInformation
        request:(NSURLRequest *)request
        frame:(WebFrame *)frame
        decisionListener:(id <WebPolicyDecisionListener>)listener
{
    BOOL handledExternally = NO;
    if (self.navigationHandler) {
        handledExternally = self.navigationHandler(self, request);
    }

    if (handledExternally) {
        [listener ignore];
    } else {
        [listener use];
    }
}

- (void)webView:(WebView *)sender
decidePolicyForNewWindowAction:(NSDictionary *)actionInformation
        request:(NSURLRequest *)request
   newFrameName:(NSString *)frameName
decisionListener:(id<WebPolicyDecisionListener>)listener
{
    BOOL handled = NO;
    if (self.newWindowHandler) {
        handled = self.newWindowHandler(self, request);
    }
    if (!handled && self.navigationHandler) {
        handled = self.navigationHandler(self, request);
    }

    if (handled) {
        [listener ignore];
    } else {
        [listener use];
    }
}

- (void)webView:(WebView *)webView addMessageToConsole:(NSDictionary *)dictionary
{
    NSLog(@"Error from webkit: %@", dictionary);
}

- (NSArray *)webView:(WebView *)sender contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:(NSArray *)defaultMenuItems
{
    if (self.contextMenuHandler) {
        NSArray *menuItems = self.contextMenuHandler(self, element, defaultMenuItems);
        if (menuItems) {
            return menuItems;
        }
    }
    return defaultMenuItems;
}

#pragma mark - Cleanup

- (void)dealloc
{
    _webView.UIDelegate = nil;
    _webView.frameLoadDelegate = nil;
    _webView.policyDelegate = nil;
    _webView.resourceLoadDelegate = nil;
}

@end
