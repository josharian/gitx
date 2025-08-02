//
//  PBGitRevList.m
//  GitX
//
//  Created by Pieter de Bie on 17-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitRevList.h"
#import "PBGitRepository.h"
#import "PBGitCommit.h"
#import "PBGitGrapher.h"
#import "PBGitRevSpecifier.h"
#import "PBEasyPipe.h"
#import "PBGitBinary.h"
#import "GTObjectiveGitStubs.h"


// #import <ObjectiveGit/ObjectiveGit.h>

#import <iostream>
#import <string>
#import <map>
// #import <ObjectiveGit/GTOID.h>

// GT* stub implementations
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
@synthesize repository;
@synthesize commitQueue;

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

- (void)resetWithOptions:(GTEnumeratorOptions)options { 
    [self.commitQueue removeAllObjects];
    [self.revListArgs removeAllObjects];
    self.options = options;
    self.hasPopulated = NO;
}

- (void)pushGlob:(NSString *)glob error:(NSError **)error { 
    [self.revListArgs addObject:[@"--glob=" stringByAppendingString:glob]];
}

- (void)pushSHA:(NSString *)sha error:(NSError **)error { 
    if (sha && [sha length] > 0) {
        [self.revListArgs addObject:sha];
    }
}

- (GTCommit *)nextObjectWithSuccess:(BOOL *)success error:(NSError **)error {
    // If we haven't populated the queue yet, do it now using git rev-list
    if (self.commitQueue.count == 0 && !self.hasPopulated) {
        NSLog(@"GITX_DEBUG: Populating commit queue");
        [self populateQueueWithRevList];
        self.hasPopulated = YES;
        NSLog(@"GITX_DEBUG: Queue populated with %lu commits", (unsigned long)self.commitQueue.count);
    }
    
    NSLog(@"GITX_DEBUG: Checking queue count: %lu", (unsigned long)self.commitQueue.count);
    if (self.commitQueue.count > 0) {
        GTCommit *commit = [self.commitQueue firstObject];
        [self.commitQueue removeObjectAtIndex:0];
        NSLog(@"GITX_DEBUG: Returning commit %@, %lu commits remaining", [commit.SHA substringToIndex:7], (unsigned long)self.commitQueue.count);
        
        if (success) *success = YES;
        return commit;
    }
    
    NSLog(@"GITX_DEBUG: No more commits available (queue count is 0)");
    if (success) *success = NO;
    return nil;
}

- (void)populateQueueWithRevList {
    PBGitRepository *pbRepo = self.repository;
    if (!pbRepo || self.revListArgs.count == 0) {
        NSLog(@"GTEnumerator: Cannot populate - no repository or no rev args");
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
    
    NSLog(@"GTEnumerator: Running git with args: %@", args);
    NSLog(@"GTEnumerator: Working directory: %@", [pbRepo workingDirectory]);
    
    NSTask *gitTask = [[NSTask alloc] init];
    gitTask.launchPath = @"/usr/bin/git";
    gitTask.arguments = args;
    gitTask.currentDirectoryPath = [pbRepo workingDirectory];
    
    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    gitTask.standardOutput = outputPipe;
    gitTask.standardError = errorPipe;
    
    @try {
        NSLog(@"GTEnumerator: About to launch git task");
        [gitTask launch];
        NSLog(@"GTEnumerator: Git task launched, reading output immediately");
        
        // Read output immediately to prevent deadlock
        NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
        NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
        
        [gitTask waitUntilExit];
        NSLog(@"GTEnumerator: Git task completed with status: %d", gitTask.terminationStatus);
        
        NSString *errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
        
        if (gitTask.terminationStatus == 0) {
            NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
            [self parseRevListOutput:output];
            
            NSLog(@"GTEnumerator: Added %lu commits to queue", (unsigned long)self.commitQueue.count);
        } else {
            NSLog(@"GTEnumerator: git rev-list failed with status %d, error: %@", gitTask.terminationStatus, errorOutput);
        }
    } @catch (NSException *exception) {
        NSLog(@"GTEnumerator: Exception running git rev-list: %@", exception);
    }
}

- (void)parseRevListOutput:(NSString *)output {
    NSLog(@"🔍 GITX_PARSE: Starting to parse rev-list output, length: %lu", (unsigned long)[output length]);
    NSLog(@"🔍 GITX_PARSE: First 200 chars of raw output: %@", [output substringToIndex:MIN(200, [output length])]);
    
    NSArray *commits = [output componentsSeparatedByString:@"\ncommit "];
    NSLog(@"🔍 GITX_PARSE: Split into %lu commit blocks", (unsigned long)[commits count]);
    
    int processedCount = 0;
    for (NSString *commitBlock in commits) {
        if ([commitBlock length] == 0) continue;
        
        // Handle the first commit which might not have the \ncommit prefix
        NSString *block = commitBlock;
        if ([block hasPrefix:@"commit "]) {
            block = [block substringFromIndex:7];
        }
        
        NSLog(@"🔍 GITX_PARSE: Processing block %d, first 100 chars: %@", processedCount, [block substringToIndex:MIN(100, [block length])]);
        
        // Find the first newline - the SHA is on the first line, then NUL-separated data follows
        NSRange firstNewline = [block rangeOfString:@"\n"];
        if (firstNewline.location == NSNotFound) {
            NSLog(@"🔍 GITX_PARSE: No newline found in block, skipping");
            continue;
        }
        
        NSString *firstLine = [block substringToIndex:firstNewline.location];
        NSString *dataSection = [block substringFromIndex:firstNewline.location + 1];
        
        NSLog(@"🔍 GITX_PARSE: First line (SHA): '%@'", firstLine);
        NSLog(@"🔍 GITX_PARSE: Data section length: %lu", (unsigned long)[dataSection length]);
        
        // Split the data section by NUL characters
        NSArray *fields = [dataSection componentsSeparatedByString:@"\0"];
        NSLog(@"🔍 GITX_PARSE: Split into %lu fields", (unsigned long)[fields count]);
        
        if ([fields count] >= 7) {  // We need: SHA, subject, body, author, committer, timestamp, parents
            processedCount++;
            
            // Parse according to git format: %H%x00%s%x00%B%x00%an%x00%cn%x00%ct%x00%P%x00
            NSString *shaString = [firstLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *shaString2 = fields[0]; // Duplicate SHA from format
            NSString *messageSummary = fields[1];
            NSString *message = fields[2];
            NSString *authorName = fields[3];
            NSString *committerName = fields[4];
            NSString *timestampString = fields[5];
            NSString *parentSHAsString = fields[6];
            
            NSLog(@"🔍 GITX_PARSE: Commit %d:", processedCount);
            NSLog(@"🔍 GITX_PARSE:   SHA from line: '%@'", shaString);
            NSLog(@"🔍 GITX_PARSE:   SHA from field: '%@'", shaString2);
            NSLog(@"🔍 GITX_PARSE:   Subject: '%@'", messageSummary);
            NSLog(@"🔍 GITX_PARSE:   Author: '%@'", authorName);
            NSLog(@"🔍 GITX_PARSE:   Timestamp: '%@'", timestampString);
            NSLog(@"🔍 GITX_PARSE:   Parents: '%@'", parentSHAsString);
            
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
                
                NSLog(@"🔍 GITX_PARSE:   Parsed timestamp %@ -> %f -> %@", timestampString, timestamp, commit.commitDate);
                
                // Parse parent commit SHAs
                NSMutableArray *parentCommits = [NSMutableArray array];
                if ([parentSHAsString length] > 0) {
                    NSArray *parentSHAs = [parentSHAsString componentsSeparatedByString:@" "];
                    NSLog(@"🔍 GITX_PARSE:   Found %lu parent SHAs", (unsigned long)[parentSHAs count]);
                    for (NSString *parentSHA in parentSHAs) {
                        NSString *trimmedSHA = [parentSHA stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                        NSLog(@"🔍 GITX_PARSE:     Parent SHA: '%@' (length: %lu)", trimmedSHA, (unsigned long)[trimmedSHA length]);
                        if ([trimmedSHA length] >= 40) {
                            GTCommit *parentCommit = [[GTCommit alloc] init];
                            parentCommit.SHA = trimmedSHA;
                            parentCommit.OID = [GTOID oidWithSHA:trimmedSHA];
                            [parentCommits addObject:parentCommit];
                            NSLog(@"🔍 GITX_PARSE:     Added parent commit");
                        }
                    }
                }
                commit.parents = parentCommits;
                NSLog(@"🔍 GITX_PARSE:   Final parent count: %lu", (unsigned long)[parentCommits count]);
                
                // Create GTOID for the SHA
                GTOID *oid = [GTOID oidWithSHA:shaString];
                commit.OID = oid;
                
                [self.commitQueue addObject:commit];
                NSLog(@"🔍 GITX_PARSE:   Added commit to queue");
            } else {
                NSLog(@"🔍 GITX_PARSE: SHA too short (%lu chars), skipping", (unsigned long)[shaString length]);
            }
        } else {
            NSLog(@"🔍 GITX_PARSE: Not enough fields (%lu), skipping", (unsigned long)[fields count]);
        }
        
        // Removed debugging limit - process all commits
    }
    NSLog(@"🔍 GITX_PARSE: Finished parsing, total commits: %lu", (unsigned long)[self.commitQueue count]);
}
@end

using namespace std;


@interface PBGitRevList ()

@property (nonatomic, assign) BOOL isGraphing;
@property (nonatomic, assign) BOOL resetCommits;

@property (nonatomic, weak) PBGitRepository *repository;
@property (nonatomic, strong) PBGitRevSpecifier *currentRev;

@property (nonatomic, strong) NSMutableDictionary *commitCache;

@property (nonatomic, strong) NSThread *parseThread;

@end


#define kRevListRevisionsKey @"revisions"


@implementation PBGitRevList

- (id) initWithRepository:(PBGitRepository *)repo rev:(PBGitRevSpecifier *)rev shouldGraph:(BOOL)graph
{
	self = [super init];
	if (!self) {
		return nil;
	}
	self.repository = repo;
	self.currentRev = [rev copy];
	self.isGraphing = graph;
	self.commitCache = [NSMutableDictionary new];
	
	return self;
}


- (void) loadRevisons
{
	[self cancel];
	
	self.parseThread = [[NSThread alloc] initWithTarget:self selector:@selector(beginWalkWithSpecifier:) object:self.currentRev];
	self.isParsing = YES;
	self.resetCommits = YES;
	[self.parseThread start];
}


- (void)cancel
{
	[self.parseThread cancel];
	self.parseThread = nil;
	self.isParsing = NO;
}


- (void) finishedParsing
{
	self.parseThread = nil;
	self.isParsing = NO;
}


- (void) updateCommits:(NSDictionary *)update
{
	NSArray *revisions = [update objectForKey:kRevListRevisionsKey];
	NSLog(@"🔍 GITX_UPDATE: updateCommits called with %lu revisions", (unsigned long)[revisions count]);
	
	if (!revisions || [revisions count] == 0) {
		NSLog(@"🔍 GITX_UPDATE: No revisions to update, returning");
		return;
	}
	
	if (self.resetCommits) {
		self.commits = [NSMutableArray array];
		self.resetCommits = NO;
		NSLog(@"🔍 GITX_UPDATE: Reset commits array");
	}
	
	NSRange range = NSMakeRange([self.commits count], [revisions count]);
	NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:range];
	
	NSLog(@"🔍 GITX_UPDATE: Adding %lu commits to UI, total will be %lu", (unsigned long)[revisions count], (unsigned long)([self.commits count] + [revisions count]));
	
	[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@"commits"];
	[self.commits addObjectsFromArray:revisions];
	[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@"commits"];
	
	NSLog(@"🔍 GITX_UPDATE: UI update complete, total commits: %lu", (unsigned long)[self.commits count]);
}

- (void) beginWalkWithSpecifier:(PBGitRevSpecifier*)rev
{
	PBGitRepository *pbRepo = self.repository;
	GTRepository *repo = pbRepo.gtRepo;
	
	NSError *error = nil;
	GTEnumerator *enu = [[GTEnumerator alloc] initWithRepository:pbRepo error:&error];
	
	[self setupEnumerator:enu forRevspec:rev inRepository:pbRepo];
	
	[self addCommitsFromEnumerator:enu inPBRepo:pbRepo];
}

- (void) addGitObject:(GTObject *)obj toCommitSet:(NSMutableSet *)set
{
	GTCommit *commit = nil;
	if ([obj isKindOfClass:[GTCommit class]]) {
		commit = (GTCommit *)obj;
	} else {
		NSError *peelError = nil;
		commit = [obj objectByPeelingToType:GTObjectTypeCommit error:&peelError];
	}

	NSAssert(commit, @"Can't add nil commit to set");

	for (GTCommit *item in set) {
		if ([item.OID isEqual:commit.OID]) {
			return;
		}
	}

	[set addObject:commit];
}

- (void) addGitBranches:(NSArray *)branches fromRepo:(GTRepository *)repo toCommitSet:(NSMutableSet *)set
{
	for (GTBranch *branch in branches) {
		GTCommit *commit = [[GTCommit alloc] init];
		commit.SHA = branch.SHA;
		[self addGitObject:commit toCommitSet:set];
	}
}

- (void) setupEnumerator:(GTEnumerator*)enumerator
			  forRevspec:(PBGitRevSpecifier*)rev
		     inRepository:(PBGitRepository*)pbRepo
{
	[enumerator resetWithOptions:GTEnumeratorOptionsTopologicalSort];
	
	if (rev.isSimpleRef) {
		// Simple ref - just push it directly to rev-list
		[enumerator pushSHA:rev.simpleRef error:nil];
	} else {
		// Complex revspec - pass all parameters to git rev-list
		for (NSString *param in rev.parameters) {
			[enumerator pushSHA:param error:nil];
		}
	}
}

- (void) addCommitsFromEnumerator:(GTEnumerator *)enumerator
						 inPBRepo:(PBGitRepository*)pbRepo;
{
	PBGitGrapher *g = [[PBGitGrapher alloc] initWithRepository:pbRepo];
	__block NSDate *lastUpdate = [NSDate date];

	dispatch_queue_t loadQueue = dispatch_queue_create("net.phere.gitx.loadQueue", 0);
	dispatch_queue_t decorateQueue = dispatch_queue_create("net.phere.gitx.decorateQueue", 0);
	dispatch_group_t loadGroup = dispatch_group_create();
	dispatch_group_t decorateGroup = dispatch_group_create();
	
	BOOL enumSuccess = FALSE;
	GTCommit *commit = nil;
	__block int num = 0;
	__block NSMutableArray *revisions = [NSMutableArray array];
	NSError *enumError = nil;
	
	NSLog(@"🔍 GITX_ENUM: Starting enumeration loop");
	while ((commit = [enumerator nextObjectWithSuccess:&enumSuccess error:&enumError]) && enumSuccess) {
		NSLog(@"🔍 GITX_ENUM: Got commit %d from enumerator: %@", num, [commit.SHA substringToIndex:7]);
		//GTOID *oid = [[GTOID alloc] initWithSHA:commit.sha];
		
		dispatch_group_async(loadGroup, loadQueue, ^{
			NSLog(@"🔍 GITX_PBCOMMIT: Processing GTCommit %@ with %lu parents, date: %@", [commit.SHA substringToIndex:7], (unsigned long)[commit.parents count], commit.commitDate);
			
			PBGitCommit *newCommit = nil;
			PBGitCommit *cachedCommit = [self.commitCache objectForKey:commit.SHA];
			if (cachedCommit) {
				newCommit = cachedCommit;
				NSLog(@"🔍 GITX_PBCOMMIT: Using cached PBGitCommit for %@, date: %@, parents: %lu", [commit.SHA substringToIndex:7], newCommit.date, (unsigned long)[newCommit.parents count]);
			} else {
				@try {
					newCommit = [[PBGitCommit alloc] initWithRepository:pbRepo andGTCommit:commit];
					[self.commitCache setObject:newCommit forKey:commit.SHA];
					NSLog(@"🔍 GITX_PBCOMMIT: Created new PBGitCommit for %@, date: %@, parents: %lu", [commit.SHA substringToIndex:7], newCommit.date, (unsigned long)[newCommit.parents count]);
				} @catch (NSException *exception) {
					NSLog(@"🔍 GITX_PBCOMMIT: CRASH creating PBGitCommit for %@: %@", [commit.SHA substringToIndex:7], exception);
					return;
				}
			}
			
			[revisions addObject:newCommit];
			
			if (self.isGraphing) {
				dispatch_group_async(decorateGroup, decorateQueue, ^{
					if (num % 50 == 0) {
						NSLog(@"GITX_DEBUG: About to decorate commit %d: %@", num, [commit.SHA substringToIndex:7]);
					}
					@try {
						[g decorateCommit:newCommit];
						if (num % 50 == 0) {
							NSLog(@"GITX_DEBUG: Finished decorating commit %d", num);
						}
					} @catch (NSException *exception) {
						NSLog(@"GITX_DEBUG: CRASH in decorateCommit for commit %d (%@): %@", num, [commit.SHA substringToIndex:7], exception);
						@throw exception;
					}
				});
			}
			
			if (++num % 100 == 0) {
				NSLog(@"🔍 GITX_BATCH: Processed %d commits, checking for batch update", num);
				if ([[NSDate date] timeIntervalSinceDate:lastUpdate] > 0.5 && ![[NSThread currentThread] isCancelled]) {
					NSLog(@"🔍 GITX_BATCH: Time threshold met, sending batch of %lu commits to UI", (unsigned long)[revisions count]);
					dispatch_group_wait(decorateGroup, DISPATCH_TIME_FOREVER);
					NSDictionary *update = [NSDictionary dictionaryWithObjectsAndKeys:revisions, kRevListRevisionsKey, nil];
					[self performSelectorOnMainThread:@selector(updateCommits:) withObject:update waitUntilDone:NO];
					revisions = [NSMutableArray array];
					lastUpdate = [NSDate date];
					NSLog(@"🔍 GITX_BATCH: Batch update sent");
				}
			}
		});
	}

	NSAssert(!enumError, @"Error enumerating commits");
	NSLog(@"🔍 GITX_FINAL: Enumeration complete, waiting for loadGroup");
	
	dispatch_group_wait(loadGroup, DISPATCH_TIME_FOREVER);
	NSLog(@"🔍 GITX_FINAL: loadGroup complete, waiting for decorateGroup");
	
	dispatch_group_wait(decorateGroup, DISPATCH_TIME_FOREVER);
	NSLog(@"🔍 GITX_FINAL: decorateGroup complete");
	
	NSLog(@"🔍 GITX_FINAL: Dispatch groups complete, checking thread cancellation");
	// Make sure the commits are stored before exiting.
	if (![[NSThread currentThread] isCancelled]) {
		NSLog(@"🔍 GITX_FINAL: Thread not cancelled, sending %lu final commits to UI", (unsigned long)[revisions count]);
		NSDictionary *update = [NSDictionary dictionaryWithObjectsAndKeys:revisions, kRevListRevisionsKey, nil];
		
		NSLog(@"🚀 NEW_RUN: About to dispatch updateCommits to main thread");
		dispatch_async(dispatch_get_main_queue(), ^{
			NSLog(@"🚀 NEW_RUN: Now on main thread, calling updateCommits");
			[self updateCommits:update];
		});
		
		NSLog(@"🚀 NEW_RUN: About to dispatch finishedParsing to main thread");
		dispatch_async(dispatch_get_main_queue(), ^{
			NSLog(@"🚀 NEW_RUN: Now on main thread, calling finishedParsing");
			[self finishedParsing];
		});
		
		NSLog(@"🔍 GITX_FINAL: Final update dispatched to UI");
	} else {
		NSLog(@"🔍 GITX_FINAL: Thread was cancelled, not sending commits to UI");
	}
}

@end
