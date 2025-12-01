//
//  PBWKGitXSchemeHandler.m
//  GitX
//

#import "PBWKGitXSchemeHandler.h"

#import "PBGitRepository.h"

static NSString * const PBWKGitXSchemeHandlerErrorDomain = @"PBWKGitXSchemeHandlerErrorDomain";

@interface PBWKGitXSchemeHandler ()
@property (nonatomic, copy) PBWKGitXRepositoryProvider repositoryProvider;
@property (nonatomic, strong) dispatch_queue_t workQueue;
@end

@implementation PBWKGitXSchemeHandler

- (instancetype)initWithRepositoryProvider:(PBWKGitXRepositoryProvider)provider
{
    NSParameterAssert(provider);
    self = [super init];
    if (!self) {
        return nil;
    }

    _repositoryProvider = [provider copy];
    _workQueue = dispatch_queue_create("com.gitx.wkwebview.gitx-scheme", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)updateRepositoryProvider:(PBWKGitXRepositoryProvider)provider
{
    @synchronized (self) {
        _repositoryProvider = [provider copy];
    }
}

- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask
{
    (void)webView;

    PBWKGitXRepositoryProvider provider = self.repositoryProvider;
    PBGitRepository *repository = provider ? provider() : nil;
    if (!repository) {
        NSError *error = [NSError errorWithDomain:PBWKGitXSchemeHandlerErrorDomain
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Repository unavailable for gitx request" }];
        [urlSchemeTask didFailWithError:error];
        return;
    }

    NSURLRequest *request = urlSchemeTask.request;
    NSURL *url = request.URL;
    if (!url) {
        NSError *error = [NSError errorWithDomain:PBWKGitXSchemeHandlerErrorDomain
                                             code:2
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Missing URL for gitx request" }];
        [urlSchemeTask didFailWithError:error];
        return;
    }

    dispatch_async(self.workQueue, ^{
        NSString *host = url.host ?: @"";
        NSString *path = url.path ?: @"";
        if ([path hasPrefix:@"/"]) {
            path = [path substringFromIndex:1];
        }

        if (host.length == 0 || path.length == 0) {
            NSError *error = [NSError errorWithDomain:PBWKGitXSchemeHandlerErrorDomain
                                                 code:3
                                             userInfo:@{ NSLocalizedDescriptionKey: @"Invalid gitx URL" }];
            dispatch_async(dispatch_get_main_queue(), ^{
                [urlSchemeTask didFailWithError:error];
            });
            return;
        }

        NSString *specifier = [NSString stringWithFormat:@"%@:%@", host, path];
        NSArray *arguments = @[ @"cat-file", @"blob", specifier ];

        NSError *gitError = nil;
        NSData *data = [repository executeGitCommandReturningData:arguments error:&gitError];

        if (!data) {
            NSError *error = [NSError errorWithDomain:PBWKGitXSchemeHandlerErrorDomain
                                                 code:5
                                             userInfo:@{ NSLocalizedDescriptionKey: @"Failed to load gitx resource" }];
            dispatch_async(dispatch_get_main_queue(), ^{
                [urlSchemeTask didFailWithError:error];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            NSURLResponse *response = [[NSURLResponse alloc] initWithURL:url
                                                                 MIMEType:nil
                                                    expectedContentLength:(NSInteger)data.length
                                                         textEncodingName:nil];
            [urlSchemeTask didReceiveResponse:response];
            if (data.length > 0) {
                [urlSchemeTask didReceiveData:data];
            }
            [urlSchemeTask didFinish];
        });
    });
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask
{
    // Tasks are short-lived and executed on a serial queue; nothing to cancel explicitly.
    (void)webView;
    (void)urlSchemeTask;
}

@end
