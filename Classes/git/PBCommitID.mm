//
//  PBCommitID.mm
//  GitX
//
//  Lightweight replacement for GTOID
//

#import "PBCommitID.h"

@implementation PBCommitID

@synthesize sha = _sha;

+ (instancetype)commitIDWithSHA:(NSString *)sha {
    PBCommitID *commitID = [[PBCommitID alloc] init];
    commitID->_sha = [sha copy];
    
    commitID->_git_oid = (git_oid*)malloc(sizeof(git_oid));
    
    if ([sha length] >= 40) {
        const char *hexString = [sha UTF8String];
        for (int i = 0; i < 20; i++) {
            sscanf(hexString + (i * 2), "%2hhx", &commitID->_git_oid->id[i]);
        }
    } else {
        memset(commitID->_git_oid, 0, sizeof(git_oid));
    }
    
    return commitID;
}

- (NSString *)SHA {
    return self.sha;
}

- (const git_oid *)git_oid {
    return _git_oid;
}

- (void)dealloc {
    if (_git_oid) {
        free(_git_oid);
    }
}

- (BOOL)isEqual:(id)object {
    if ([object isKindOfClass:[PBCommitID class]]) {
        return [self.sha isEqualToString:((PBCommitID *)object).sha];
    } else if ([object isKindOfClass:[NSString class]]) {
        return [self.sha isEqualToString:(NSString *)object];
    }
    return NO;
}

- (NSUInteger)hash {
    return [self.sha hash];
}

- (id)copyWithZone:(NSZone *)zone {
    return [PBCommitID commitIDWithSHA:self.sha];
}

@end

@implementation PBCommitID (JavaScript)

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector {
    return NO;
}

+ (BOOL)isKeyExcludedFromWebScript:(const char *)name {
    return NO;
}

@end