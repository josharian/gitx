//
//  PBCommitID.h
//  GitX
//
//  Lightweight replacement for GTOID
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
#include "PBGitLane.h"
#else
typedef struct {
    unsigned char id[20];
} git_oid;
#endif

@interface PBCommitID : NSObject <NSCopying> {
    NSString *_sha;
    git_oid *_git_oid;
}

@property (readonly) NSString *sha;
@property (readonly) NSString *SHA;
@property (readonly) const git_oid *git_oid;

+ (instancetype)commitIDWithSHA:(NSString *)sha;
- (BOOL)isEqual:(id)object;
- (NSUInteger)hash;

@end

@interface PBCommitID (JavaScript)
@end