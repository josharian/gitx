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
#import "GTObjectiveGitStubs.h"


// #import <ObjectiveGit/ObjectiveGit.h>

#import <iostream>
#import <string>
#import <map>
// #import <ObjectiveGit/GTOID.h>



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
		// Inline the objectByPeelingToType logic - just create a new GTCommit
		commit = [[GTCommit alloc] init];
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
