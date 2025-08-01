//
//  GTOID+JavaScript.h
//  GitX
//
//  Created by Sven Weidauer on 18.05.14.
//
//

// #import <ObjectiveGit/ObjectiveGit.h>

#ifdef __cplusplus
// When compiled as C++, include PBGitLane.h for git_oid definition
#include "PBGitLane.h"
#else
// When compiled as Objective-C, define git_oid locally
typedef struct {
    unsigned char id[20]; // SHA-1 is 20 bytes
} git_oid;
#endif

@interface GTOID : NSObject {
	NSString *_sha;
	git_oid *_git_oid;
}
@property (readonly) NSString *sha;
@property (readonly) NSString *SHA; // Alias for sha with different case
@property (readonly) const git_oid *git_oid; // For compatibility with PBGitGrapher
+ (instancetype)oidWithSHA:(NSString *)sha;
- (BOOL)isEqual:(id)object;
@end

@interface GTOID (JavaScript)

@end
