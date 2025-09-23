//
//  PBGitHistoryGrapher.m
//  GitX
//
//  Created by Nathan Kinsinger on 2/20/10.
//  Copyright 2010 Nathan Kinsinger. All rights reserved.
//

#import "PBGitHistoryGrapher.h"
#import "PBGitGrapher.h"
#import "GitX-Swift.h"

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
	if ([commits count] == 0) {
		return;
	}
	NSDictionary *commitData = [NSDictionary dictionaryWithObjectsAndKeys:currentQueue, kCurrentQueueKey, commits, kNewCommitsKey, nil];
	[delegate performSelectorOnMainThread:@selector(updateCommitsFromGrapher:) withObject:commitData waitUntilDone:NO];
}


- (void) graphCommits:(NSArray *)revList
{
	if (!revList || [revList count] == 0) {
		return;
	}

	//NSDate *start = [NSDate date];
	NSThread *currentThread = [NSThread currentThread];
	NSDate *lastUpdate = [NSDate date];
	NSMutableArray *commits = [NSMutableArray array];
	NSInteger counter = 0;
	NSInteger addedCount = 0;
	NSInteger skippedCount = 0;

	@try {
		for (PBGitCommit *commit in revList) {
		if ([currentThread isCancelled]) {
			return;
		}
		NSString *commitSHA = [commit sha];
		if (counter % 50 == 0) {
		}
		BOOL shouldInclude = viewAllBranches || [searchSHAs containsObject:commitSHA];
		if (shouldInclude) {
			@try {
				[grapher decorateCommit:commit];
				[commits addObject:commit];
				addedCount++;
				if (!viewAllBranches) {
					[searchSHAs removeObject:commitSHA];
					// Parent SHAs are already PBCommitID objects
					NSArray *parentCommitIDs = [commit parents];
					for (NSString *parentCommitID in parentCommitIDs) {
						[searchSHAs addObject:parentCommitID];
					}
				}
			} @catch (NSException *exception) {
				// Skip this commit and continue
				skippedCount++;
			}
		} else {
			skippedCount++;
			if (skippedCount <= 5) {
			}
		}
		if (++counter % 100 == 0) {
			if ([[NSDate date] timeIntervalSinceDate:lastUpdate] > 0.5) {
				[self sendCommits:commits];
				commits = [NSMutableArray array];
				lastUpdate = [NSDate date];
			}
		}
		}
	} @catch (NSException *exception) {
	}
	//NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];
	//NSLog(@"Graphed %i commits in %f seconds (%f/sec)", counter, duration, counter/duration);

	[self sendCommits:commits];
	[delegate performSelectorOnMainThread:@selector(finishedGraphing) withObject:nil waitUntilDone:NO];
}


@end
