//
//  GTObjectiveGitStubs.m
//  GitX
//
//  Stub implementations to replace ObjectiveGit dependencies
//

#import "GTObjectiveGitStubs.h"
#import "PBGitRepository.h"
#import "GTOID+JavaScript.h"

@implementation GTSignature
@end

@implementation GTCommit
@end

@implementation GTObject
@end

@implementation GTRepository
@end

@implementation GTEnumerator
@synthesize repository;
@synthesize commitQueue;
@synthesize revListArgs;
@synthesize options;
@synthesize hasPopulated;

- (id)initWithRepository:(id)repo error:(NSError **)error { 
    self = [super init];
    if (self) {
        self.repository = repo;
        self.commitQueue = [[NSMutableArray alloc] init];
        self.options = GTEnumeratorOptionsNone;
        self.revListArgs = [[NSMutableArray alloc] init];
        self.hasPopulated = NO;
    }
    return self; 
}

- (void)resetWithOptions:(GTEnumeratorOptions)anOptions { 
    [self.commitQueue removeAllObjects];
    [self.revListArgs removeAllObjects];
    self.options = anOptions;
    self.hasPopulated = NO;
}

- (BOOL)pushGlob:(NSString *)glob error:(NSError **)error { 
    [self.revListArgs addObject:[@"--glob=" stringByAppendingString:glob]];
    return YES;
}

- (BOOL)pushSHA:(NSString *)sha error:(NSError **)error { 
    if (sha && [sha length] > 0) {
        [self.revListArgs addObject:sha];
        return YES;
    }
    return NO;
}

- (GTCommit *)nextObjectWithSuccess:(BOOL *)success error:(NSError **)error {
    // If we haven't populated the queue yet, do it now using git rev-list
    if (self.commitQueue.count == 0 && !self.hasPopulated) {
        [self populateQueueWithRevList];
        self.hasPopulated = YES;
    }
    
    if (self.commitQueue.count > 0) {
        GTCommit *commit = [self.commitQueue firstObject];
        [self.commitQueue removeObjectAtIndex:0];
        
        if (success) *success = YES;
        return commit;
    }
    
    if (success) *success = NO;
    return nil;
}

- (void)populateQueueWithRevList {
    PBGitRepository *pbRepo = self.repository;
    if (!pbRepo || self.revListArgs.count == 0) {
        return;
    }
    
    NSMutableArray *args = [[NSMutableArray alloc] initWithObjects:@"rev-list", nil];
    
    // Add format to get commit data including parents in one call - use NUL separators to handle newlines in commit messages
    [args addObject:@"--pretty=format:%H%x00%s%x00%B%x00%an%x00%cn%x00%ct%x00%P%x00"];
    
    // Add sorting options based on GTEnumeratorOptions
    if (self.options & GTEnumeratorOptionsTopologicalSort) {
        [args addObject:@"--topo-order"];
    } else if (self.options & GTEnumeratorOptionsTimeSort) {
        [args addObject:@"--date-order"];
    }
    
    // Add all the revisions/globs that were pushed
    [args addObjectsFromArray:self.revListArgs];
    
    // Use PBGitRepository's executeGitCommand for consistency
    NSError *error = nil;
    NSString *output = [pbRepo executeGitCommand:args inWorkingDir:YES error:&error];
    
    if (error) {
        NSLog(@"Git rev-list command failed with error: %@", error.localizedDescription);
    } else if (output) {
        [self parseRevListOutput:output];
    }
}

- (void)parseRevListOutput:(NSString *)output {
    
    NSArray *commits = [output componentsSeparatedByString:@"\ncommit "];
    
    int processedCount = 0;
    for (NSString *commitBlock in commits) {
        if ([commitBlock length] == 0) continue;
        
        // Handle the first commit which might not have the \ncommit prefix
        NSString *block = commitBlock;
        if ([block hasPrefix:@"commit "]) {
            block = [block substringFromIndex:7];
        }
        
        
        // Find the first newline - skip the commit SHA line, get the NUL-separated data
        NSRange firstNewline = [block rangeOfString:@"\n"];
        if (firstNewline.location == NSNotFound) {
            continue;
        }
        
        NSString *dataSection = [block substringFromIndex:firstNewline.location + 1];
        
        
        // Split the data section by NUL characters
        NSArray *fields = [dataSection componentsSeparatedByString:@"\0"];
        
        if ([fields count] >= 7) {  // We need: SHA, subject, body, author, committer, timestamp, parents
            processedCount++;
            
            // Parse according to git format: %H%x00%s%x00%B%x00%an%x00%cn%x00%ct%x00%P%x00
            NSString *shaString = fields[0]; // SHA from format string
            NSString *messageSummary = fields[1];
            NSString *message = fields[2];
            NSString *authorName = fields[3];
            NSString *committerName = fields[4];
            NSString *timestampString = fields[5];
            NSString *parentSHAsString = fields[6];
            
            
            if ([shaString length] >= 40) {
                GTCommit *commit = [[GTCommit alloc] init];
                commit.SHA = shaString;
                commit.shortSHA = [shaString substringToIndex:MIN(7, [shaString length])];
                commit.messageSummary = messageSummary;
                commit.message = message;
                
                GTSignature *author = [[GTSignature alloc] init];
                author.name = authorName;
                commit.author = author;
                
                GTSignature *committer = [[GTSignature alloc] init];
                committer.name = committerName;
                commit.committer = committer;
                
                NSTimeInterval timestamp = [timestampString doubleValue];
                commit.commitDate = [NSDate dateWithTimeIntervalSince1970:timestamp];
                
                
                // Parse parent commit SHAs
                NSMutableArray *parentCommits = [NSMutableArray array];
                if ([parentSHAsString length] > 0) {
                    NSArray *parentSHAs = [parentSHAsString componentsSeparatedByString:@" "];
                    for (NSString *parentSHA in parentSHAs) {
                        NSString *trimmedSHA = [parentSHA stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                        if ([trimmedSHA length] >= 40) {
                            GTCommit *parentCommit = [[GTCommit alloc] init];
                            parentCommit.SHA = trimmedSHA;
                            parentCommit.OID = [GTOID oidWithSHA:trimmedSHA];
                            [parentCommits addObject:parentCommit];
                        }
                    }
                }
                commit.parents = parentCommits;
                
                // Create GTOID for the SHA
                GTOID *oid = [GTOID oidWithSHA:shaString];
                commit.OID = oid;
                
                [self.commitQueue addObject:commit];
            }
        }
    }
}
@end