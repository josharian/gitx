//
//  PBWKGitXSchemeHandler.h
//  GitX
//
//  Created by ChatGPT on 2024-XX-XX.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class PBGitRepository;

NS_ASSUME_NONNULL_BEGIN

typedef PBGitRepository * _Nullable (^PBWKGitXRepositoryProvider)(void);

@interface PBWKGitXSchemeHandler : NSObject <WKURLSchemeHandler>

- (instancetype)initWithRepositoryProvider:(PBWKGitXRepositoryProvider)provider NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
