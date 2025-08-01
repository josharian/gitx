//
//  GTObjectiveGitStubs.m
//  GitX
//
//  REPLACE WITH GIT EXEC - Temporary stub implementations to replace ObjectiveGit dependencies
//

#import "GTObjectiveGitStubs.h"

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

@implementation GTEnumerator
- (id)initWithRepository:(id)repo error:(NSError **)error { 
    self.repository = repo;
    return self; 
}
- (void)resetWithOptions:(NSUInteger)options { }
- (void)pushGlob:(NSString *)glob error:(NSError **)error { }
- (void)pushSHA:(NSString *)sha error:(NSError **)error { }
- (GTCommit *)nextObjectWithSuccess:(BOOL *)success error:(NSError **)error {
    // REPLACE WITH GIT EXEC - Stub that returns nil to end enumeration
    if (success) *success = NO;
    return nil;
}
@end