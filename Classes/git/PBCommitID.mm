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
    return commitID;
}

- (NSString *)SHA {
    return self.sha;
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