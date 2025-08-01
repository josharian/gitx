//
//  GTObjectiveGitStubs.m
//  GitX
//
//  Stub implementations to replace ObjectiveGit dependencies
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

@implementation GTRepository
@end

@implementation GTEnumerator
- (id)initWithRepository:(id)repo error:(NSError **)error { 
    self.repository = repo;
    self.shaQueue = [[NSMutableArray alloc] init];
    return self; 
}
- (void)resetWithOptions:(GTEnumeratorOptions)options { 
    [self.shaQueue removeAllObjects];
}
- (void)pushGlob:(NSString *)glob error:(NSError **)error { }
- (void)pushSHA:(NSString *)sha error:(NSError **)error { 
    if (sha && [sha length] > 0) {
        [self.shaQueue addObject:sha];
    }
}
- (GTCommit *)nextObjectWithSuccess:(BOOL *)success error:(NSError **)error {
    if (self.shaQueue.count > 0) {
        NSString *sha = [self.shaQueue firstObject];
        [self.shaQueue removeObjectAtIndex:0];
        
        GTCommit *commit = [[GTCommit alloc] init];
        commit.SHA = sha;
        commit.shortSHA = [sha substringToIndex:MIN(7, [sha length])];
        
        GTOID *oid = [GTOID oidWithSHA:sha];
        commit.OID = oid;
        
        if (success) *success = YES;
        return commit;
    }
    
    if (success) *success = NO;
    return nil;
}
@end