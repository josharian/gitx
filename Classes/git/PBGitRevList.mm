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


// #import <ObjectiveGit/ObjectiveGit.h>

#import <iostream>
#import <string>
#import <map>
// #import <ObjectiveGit/GTOID.h>

// All ObjectiveGit stubs are now in GTObjectiveGitStubs.h/.m

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
	if (!revisions || [revisions count] == 0)
		return;
	
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
	GTEnumerator *enu = [[GTEnumerator alloc] initWithRepository:repo error:&error];
	
	[self setupEnumerator:enu forRevspec:rev];
	
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
{
	[enumerator resetWithOptions:GTEnumeratorOptionsTopologicalSort];
	NSMutableSet *enumCommits = [NSMutableSet new];
	if (rev.isSimpleRef) {
		// Use git show to resolve the ref to a commit SHA
		NSTask *gitTask = [[NSTask alloc] init];
		gitTask.launchPath = @"/usr/bin/git";
		gitTask.arguments = @[@"show", @"--format=%H", @"--no-patch", rev.simpleRef];
		gitTask.currentDirectoryPath = [rev.workingDirectory path];
		
		NSPipe *outputPipe = [NSPipe pipe];
		gitTask.standardOutput = outputPipe;
		gitTask.standardError = [NSPipe pipe];
		
		[gitTask launch];
		[gitTask waitUntilExit];
		
		if (gitTask.terminationStatus == 0) {
			NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
			NSString *commitSHA = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
			commitSHA = [commitSHA stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			
			if ([commitSHA length] >= 40) {
				[enumerator pushSHA:commitSHA error:nil];
			}
		}
	} else {
		// NSArray *allRefs = [repo referenceNamesWithError:&error];
		for (NSString *param in rev.parameters) {
			if ([param isEqualToString:@"--branches"]) {
				NSTask *gitTask = [[NSTask alloc] init];
				gitTask.launchPath = @"/usr/bin/git";
				gitTask.arguments = @[@"for-each-ref", @"--format=%(objectname)", @"refs/heads/"];
				gitTask.currentDirectoryPath = [rev.workingDirectory path];
				
				NSPipe *outputPipe = [NSPipe pipe];
				gitTask.standardOutput = outputPipe;
				gitTask.standardError = [NSPipe pipe];
				
				[gitTask launch];
				[gitTask waitUntilExit];
				
				if (gitTask.terminationStatus == 0) {
					NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
					NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
					NSArray *shas = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
					
					for (NSString *sha in shas) {
						NSString *trimmedSHA = [sha stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
						if ([trimmedSHA length] >= 40) {
							[enumerator pushSHA:trimmedSHA error:nil];
						}
					}
				}
			} else if ([param isEqualToString:@"--remotes"]) {
				// NSArray *branches = [repo remoteBranchesWithError:&error];
				// [self addGitBranches:branches fromRepo:repo toCommitSet:enumCommits];
			} else if ([param isEqualToString:@"--tags"]) {
				// for (NSString *ref in allRefs) {
				// 	if ([ref hasPrefix:@"refs/tags/"]) {
				// 		GTObject *tag = [repo lookUpObjectByRevParse:ref error:&error];
				// 		GTCommit *commit = nil;
				// 		if ([tag isKindOfClass:[GTCommit class]]) {
				// 			commit = (GTCommit *)tag;
				// 		} else if ([tag isKindOfClass:[GTTag class]]) {
				// 			NSError *tagError = nil;
				// 			commit = [(GTTag *)tag objectByPeelingTagError:&tagError];
				// 		}
				// 
				// 		if ([commit isKindOfClass:[GTCommit class]])
				// 		{
				// 			[self addGitObject:commit toCommitSet:enumCommits];
				// 		}
				// 	}
				// }
			} else if ([param hasPrefix:@"--glob="]) {
				// [enumerator pushGlob:[param substringFromIndex:@"--glob=".length] error:&error];
			} else {
				// NSError *lookupError = nil;
				// GTObject *obj = [repo lookUpObjectByRevParse:param error:&lookupError];
				// if (obj && !lookupError) {
				// 	[self addGitObject:obj toCommitSet:enumCommits];
				// } else {
				// 	[enumerator pushGlob:param error:&error];
				// }
			}
		}
	}

	NSArray *sortedBranchesAndTags = [[enumCommits allObjects] sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(id obj1, id obj2) {
		GTCommit *branchCommit1 = obj1;
		GTCommit *branchCommit2 = obj2;

		return [branchCommit2.commitDate compare:branchCommit1.commitDate];
	}];

	for (GTCommit *commit in sortedBranchesAndTags) {
		NSError *pushError = nil;
		[enumerator pushSHA:commit.SHA error:&pushError];
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
				newCommit = [[PBGitCommit alloc] initWithRepository:pbRepo andSHA:commit.SHA];
				[self.commitCache setObject:newCommit forKey:commit.SHA];
			}
			
			[revisions addObject:newCommit];
			
			if (self.isGraphing) {
				dispatch_group_async(decorateGroup, decorateQueue, ^{
					[g decorateCommit:newCommit];
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
		[self performSelectorOnMainThread:@selector(updateCommits:) withObject:update waitUntilDone:YES];
		
		[self performSelectorOnMainThread:@selector(finishedParsing) withObject:nil waitUntilDone:NO];
	}
}

@end
