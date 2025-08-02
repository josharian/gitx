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
    
    
    NSTask *gitTask = [[NSTask alloc] init];
    gitTask.launchPath = @"/usr/bin/git";
    gitTask.arguments = args;
    gitTask.currentDirectoryPath = [pbRepo workingDirectory];
    
    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    gitTask.standardOutput = outputPipe;
    gitTask.standardError = errorPipe;
    
    @try {
        [gitTask launch];
        
        // Read output immediately to prevent deadlock
        NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
        NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
        
        [gitTask waitUntilExit];
        
        NSString *errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
        
        if (gitTask.terminationStatus == 0) {
            NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
            [self parseRevListOutput:output];
            
        } else {
        }
    } @catch (NSException *exception) {
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
        
        
        // Find the first newline - the SHA is on the first line, then NUL-separated data follows
        NSRange firstNewline = [block rangeOfString:@"\n"];
        if (firstNewline.location == NSNotFound) {
            continue;
        }
        
        NSString *firstLine = [block substringToIndex:firstNewline.location];
        NSString *dataSection = [block substringFromIndex:firstNewline.location + 1];
        
        
        // Split the data section by NUL characters
        NSArray *fields = [dataSection componentsSeparatedByString:@"\0"];
        
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
            } else {
            }
        } else {
        }
        
        // Removed debugging limit - process all commits
    }
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
	
	if (!revisions || [revisions count] == 0) {
		return;
	}
	
	if (self.resetCommits) {
		self.commits = [NSMutableArray array];
		self.resetCommits = NO;
	}
	
	NSRange range = NSMakeRange([self.commits count], [revisions count]);
	NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:range];
	
	
	[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@"commits"];
	[self.commits addObjectsFromArray:revisions];
	[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@"commits"];
	
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
	
	while ((commit = [enumerator nextObjectWithSuccess:&enumSuccess error:&enumError]) && enumSuccess) {
		//GTOID *oid = [[GTOID alloc] initWithSHA:commit.sha];
		
		dispatch_group_async(loadGroup, loadQueue, ^{
			
			PBGitCommit *newCommit = nil;
			PBGitCommit *cachedCommit = [self.commitCache objectForKey:commit.SHA];
			if (cachedCommit) {
				newCommit = cachedCommit;
			} else {
				@try {
					newCommit = [[PBGitCommit alloc] initWithRepository:pbRepo andGTCommit:commit];
					[self.commitCache setObject:newCommit forKey:commit.SHA];
				} @catch (NSException *exception) {
					return;
				}
			}
			
			[revisions addObject:newCommit];
			
			if (self.isGraphing) {
				dispatch_group_async(decorateGroup, decorateQueue, ^{
					if (num % 50 == 0) {
					}
					@try {
						[g decorateCommit:newCommit];
						if (num % 50 == 0) {
						}
					} @catch (NSException *exception) {
						@throw exception;
					}
				});
			}
			
			if (++num % 100 == 0) {
				if ([[NSDate date] timeIntervalSinceDate:lastUpdate] > 0.5 && ![[NSThread currentThread] isCancelled]) {
					dispatch_group_wait(decorateGroup, DISPATCH_TIME_FOREVER);
					NSDictionary *update = [NSDictionary dictionaryWithObjectsAndKeys:revisions, kRevListRevisionsKey, nil];
					[self performSelectorOnMainThread:@selector(updateCommits:) withObject:update waitUntilDone:NO];
					revisions = [NSMutableArray array];
					lastUpdate = [NSDate date];
				}
			}
		});
	}

	NSAssert(!enumError, @"Error enumerating commits");
	
	dispatch_group_wait(loadGroup, DISPATCH_TIME_FOREVER);
	
	dispatch_group_wait(decorateGroup, DISPATCH_TIME_FOREVER);
	
	// Make sure the commits are stored before exiting.
	if (![[NSThread currentThread] isCancelled]) {
		NSDictionary *update = [NSDictionary dictionaryWithObjectsAndKeys:revisions, kRevListRevisionsKey, nil];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			[self updateCommits:update];
		});
		
		dispatch_async(dispatch_get_main_queue(), ^{
			[self finishedParsing];
		});
		
	} else {
	}
}

@end
