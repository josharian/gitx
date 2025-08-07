//
//  GTObjectiveGitStubs.m
//  GitX
//
//  Stub implementations to replace ObjectiveGit dependencies
//

#import "GTObjectiveGitStubs.h"
#import "PBGitRepository.h"

@implementation GTSignature
@end

@implementation GTCommit
@end

@implementation GTObject
- (id)objectByPeelingToType:(GTObjectType)type error:(NSError **)error {
    // Handle different object types for peeling
    switch (type) {
        case GTObjectTypeCommit:
            return [[GTCommit alloc] init];
        default:
            if (error) {
                *error = [NSError errorWithDomain:@"GTObjectError" 
                                             code:-1 
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unsupported object type for peeling"}];
            }
            return nil;
    }
}
@end

@implementation GTBranch
@end

@implementation GTTag
- (GTCommit *)objectByPeelingTagError:(NSError **)error {
    return [[GTCommit alloc] init];
}
@end

@implementation GTRepository
@end