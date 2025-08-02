//
//  PBGitHistoryGrapher.m
//  GitX
//
//  Created by Nathan Kinsinger on 2/20/10.
//  Copyright 2010 Nathan Kinsinger. All rights reserved.
//

#import "PBGitHistoryGrapher.h"
#import "PBGitGrapher.h"
#import "PBGitCommit.h"
#import "GTObjectiveGitStubs.h"

@implementation PBGitHistoryGrapher


- (id) initWithBaseCommits:(NSSet *)commits viewAllBranches:(BOOL)viewAll queue:(NSOperationQueue *)queue delegate:(id)theDelegate
{
    self = [super init];

	delegate = theDelegate;
	currentQueue = queue;
	searchSHAs = [NSMutableSet setWithSet:commits];
	grapher = [[PBGitGrapher alloc] initWithRepository:nil];
	viewAllBranches = viewAll;

	return self;
}


- (void)sendCommits:(NSArray *)commits
{
	NSLog(@"MISSING.sendCommits: sending %lu commits to delegate", (unsigned long)[commits count]);
	if ([commits count] == 0) {
		NSLog(@"MISSING.sendCommits: no commits to send, returning");
		return;
	}
	NSDictionary *commitData = [NSDictionary dictionaryWithObjectsAndKeys:currentQueue, kCurrentQueueKey, commits, kNewCommitsKey, nil];
	[delegate performSelectorOnMainThread:@selector(updateCommitsFromGrapher:) withObject:commitData waitUntilDone:NO];
}


- (void) graphCommits:(NSArray *)revList
{
	NSLog(@"MISSING.graphCommits: called with %lu commits", (unsigned long)[revList count]);
	if (!revList || [revList count] == 0) {
		NSLog(@"MISSING.graphCommits: revList is nil or empty, returning");
		return;
	}

	NSLog(@"MISSING.graphCommits: viewAllBranches = %d, searchSHAs count = %lu", viewAllBranches, (unsigned long)[searchSHAs count]);
	//NSDate *start = [NSDate date];
	NSThread *currentThread = [NSThread currentThread];
	NSDate *lastUpdate = [NSDate date];
	NSMutableArray *commits = [NSMutableArray array];
	NSInteger counter = 0;
	NSInteger addedCount = 0;
	NSInteger skippedCount = 0;

	NSLog(@"MISSING.graphCommits: about to start for loop");
	@try {
		for (PBGitCommit *commit in revList) {
			NSLog(@"MISSING.graphCommits: for loop iteration %ld started", (long)counter);
		if ([currentThread isCancelled]) {
			NSLog(@"MISSING.graphCommits: thread cancelled, returning");
			return;
		}
		GTOID *commitSHA = [commit sha];
		if (counter % 50 == 0) {
			NSLog(@"MISSING.graphCommits: processing commit %ld: %@", (long)counter, [[commitSHA description] substringToIndex:7]);
		}
		BOOL shouldInclude = viewAllBranches || [searchSHAs containsObject:commitSHA];
		if (shouldInclude) {
			@try {
				[grapher decorateCommit:commit];
				[commits addObject:commit];
				addedCount++;
				if (!viewAllBranches) {
					[searchSHAs removeObject:commitSHA];
					// Extract OIDs from parent commits
					NSArray *parentCommits = [commit parents];
					for (GTCommit *parentCommit in parentCommits) {
						[searchSHAs addObject:parentCommit.OID];
					}
				}
			} @catch (NSException *exception) {
				NSLog(@"MISSING.graphCommits: CRASH decorating commit %@: %@", [[commitSHA description] substringToIndex:7], exception);
				// Skip this commit and continue
				skippedCount++;
			}
		} else {
			skippedCount++;
			if (skippedCount <= 5) {
				NSLog(@"MISSING.graphCommits: skipping commit %@ (not in searchSHAs)", [[commitSHA description] substringToIndex:7]);
			}
		}
		if (++counter % 100 == 0) {
			NSLog(@"MISSING.graphCommits: processed %ld commits so far, added %ld", (long)counter, (long)addedCount);
			if ([[NSDate date] timeIntervalSinceDate:lastUpdate] > 0.5) {
				NSLog(@"MISSING.graphCommits: sending batch of %lu commits", (unsigned long)[commits count]);
				[self sendCommits:commits];
				commits = [NSMutableArray array];
				lastUpdate = [NSDate date];
			}
		}
		}
	} @catch (NSException *exception) {
		NSLog(@"MISSING.graphCommits: MAJOR EXCEPTION in for loop: %@", exception);
	}
	//NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];
	//NSLog(@"Graphed %i commits in %f seconds (%f/sec)", counter, duration, counter/duration);

	NSLog(@"MISSING.graphCommits: finished processing %ld commits, added %ld, skipped %ld", (long)counter, (long)addedCount, (long)skippedCount);
	NSLog(@"MISSING.graphCommits: sending final batch of %lu commits", (unsigned long)[commits count]);
	[self sendCommits:commits];
	[delegate performSelectorOnMainThread:@selector(finishedGraphing) withObject:nil waitUntilDone:NO];
}


@end
