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

@implementation GTEnumerator
- (id)initWithRepository:(id)repo error:(NSError **)error { 
    self.repository = repo;
    self.shaQueue = [[NSMutableArray alloc] init];
    return self; 
}
- (void)resetWithOptions:(GTEnumeratorOptions)options { 
    [self.shaQueue removeAllObjects];
}
- (BOOL)pushGlob:(NSString *)glob error:(NSError **)error { 
    // Cast repository to access workingDirectory method
    PBGitRepository *pbRepo = (PBGitRepository *)self.repository;
    if (!pbRepo) return NO;
    
    // Use git for-each-ref to resolve glob pattern to commit SHAs
    NSTask *gitTask = [[NSTask alloc] init];
    gitTask.launchPath = @"/usr/bin/git";
    gitTask.arguments = @[@"for-each-ref", @"--format=%(objectname)", glob];
    gitTask.currentDirectoryPath = [pbRepo workingDirectory];
    
    NSPipe *outputPipe = [NSPipe pipe];
    gitTask.standardOutput = outputPipe;
    gitTask.standardError = [NSPipe pipe];
    
    @try {
        [gitTask launch];
        [gitTask waitUntilExit];
        
        if (gitTask.terminationStatus == 0) {
            NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
            NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
            NSArray *lines = [output componentsSeparatedByString:@"\n"];
            
            for (NSString *line in lines) {
                NSString *sha = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([sha length] >= 40) {  // Valid SHA length
                    [self.shaQueue addObject:sha];
                }
            }
            return YES;
        }
    } @catch (NSException *exception) {
        // Git command failed, silently continue
    }
    return NO;
}
- (BOOL)pushSHA:(NSString *)sha error:(NSError **)error { 
    if (sha && [sha length] > 0) {
        [self.shaQueue addObject:sha];
        return YES;
    }
    return NO;
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