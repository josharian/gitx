//
//  PBGitRevList.m
//  GitX
//
//  Created by Pieter de Bie on 17-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitRevList.h"
#import "PBGitRepository.h"
#import "GitX-Swift.h"
#import "PBGitGrapher.h"
#import "PBGitRevSpecifier.h"


// #import <ObjectiveGit/ObjectiveGit.h>

// #import <ObjectiveGit/GTOID.h>


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
	
	// Use a unique delimiter that won't appear in commit messages
	// Using multiple unusual bytes: \x01GITX_COMMIT_DELIMITER\x02
	NSMutableArray *revListArgs = [NSMutableArray arrayWithObjects:@"rev-list", @"--pretty=format:\x01GITX_COMMIT_DELIMITER\x02%H%x00%s%x00%B%x00%an%x00%cn%x00%ct%x00%P%x00", @"--topo-order", nil];
	
	if (rev.isSimpleRef) {
		[revListArgs addObject:rev.simpleRef];
	} else {
		for (NSString *param in rev.parameters) {
			[revListArgs addObject:param];
		}
	}

	NSArray<NSString *> *stashSHAs = [pbRepo stashCommitSHAs];
	for (NSString *stashSha in stashSHAs) {
		if ([stashSha length] >= 40) {
			[revListArgs addObject:stashSha];
		}
	}
	
	[self addCommitsFromRevListArgs:revListArgs inPBRepo:pbRepo];
}




- (void) addCommitsFromRevListArgs:(NSMutableArray *)revListArgs
						 inPBRepo:(PBGitRepository*)pbRepo;
{
	PBGitGrapher *g = [[PBGitGrapher alloc] initWithRepository:pbRepo];
	__block NSDate *lastUpdate = [NSDate date];

	dispatch_queue_t loadQueue = dispatch_queue_create("net.phere.gitx.loadQueue", 0);
	dispatch_queue_t decorateQueue = dispatch_queue_create("net.phere.gitx.decorateQueue", 0);
	dispatch_group_t loadGroup = dispatch_group_create();
	dispatch_group_t decorateGroup = dispatch_group_create();
	
	__block int num = 0;
	__block NSMutableArray *revisions = [NSMutableArray array];
	
	// Execute git rev-list and parse output
	NSError *error = nil;
	NSString *output = [pbRepo executeGitCommand:revListArgs inWorkingDir:YES error:&error];
	
	if (error) {
		NSLog(@"Git rev-list command failed with error: %@", error.localizedDescription);
		return;
	}
	
	if (!output || [output length] == 0) {
		[self finishedParsing];
		return;
	}
	
	// Parse the output into commits using our unique delimiter
	NSArray *commits = [output componentsSeparatedByString:@"\n\x01GITX_COMMIT_DELIMITER\x02"];
	
	for (NSString *commitBlock in commits) {
		if ([commitBlock length] == 0) continue;
		if ([[NSThread currentThread] isCancelled]) break;
		
		NSString *block = commitBlock;
		
		// Handle the first commit which starts with "commit SHA\n"
		if ([block hasPrefix:@"commit "]) {
			// Skip the "commit SHA\n" line
			NSRange firstNewline = [block rangeOfString:@"\n"];
			if (firstNewline.location == NSNotFound) continue;
			block = [block substringFromIndex:firstNewline.location + 1];
			// Also skip our delimiter if it's at the start
			if ([block hasPrefix:@"\x01GITX_COMMIT_DELIMITER\x02"]) {
				block = [block substringFromIndex:[@"\x01GITX_COMMIT_DELIMITER\x02" length]];
			}
		}
		
		NSString *dataSection = block;
		
		// Split the data section by NUL characters
		NSArray *fields = [dataSection componentsSeparatedByString:@"\0"];
		
		if ([fields count] >= 7) {
			// Parse according to git format: %H%x00%s%x00%B%x00%an%x00%cn%x00%ct%x00%P%x00
			NSString *shaString = fields[0];
			NSString *messageSummary = fields[1];
			NSString *message = fields[2];
			NSString *authorName = fields[3];
			NSString *committerName = fields[4];
			NSString *timestampString = fields[5];
			NSString *parentSHAsString = fields[6];
			
				BOOL isSuppressedStash = [pbRepo isSuppressedStashCommit:shaString];
				if (isSuppressedStash) {
					continue;
				}
				BOOL isStashCommit = [pbRepo isStashCommitSHA:shaString];
				
				if ([shaString length] >= 40) {
					NSTimeInterval timestamp = [timestampString doubleValue];
					NSArray *parentSHAs = [PBCommitData parentSHAsFromString:parentSHAsString];
					if (isStashCommit && [parentSHAs count] > 1) {
						parentSHAs = @[parentSHAs[0]];
					}
					PBCommitData *commitData = [[PBCommitData alloc] initWithSha:shaString
												shortSHA:[shaString substringToIndex:MIN(7, [shaString length])]
												 message:message
											messageSummary:messageSummary
											 commitDate:[NSDate dateWithTimeIntervalSince1970:timestamp]
											 authorName:authorName
											committerName:committerName
											 parentSHAs:parentSHAs];
					
					dispatch_group_async(loadGroup, loadQueue, ^{
						PBGitCommit *newCommit = nil;
						if (isStashCommit) {
							[self.commitCache removeObjectForKey:commitData.sha];
						}
						PBGitCommit *cachedCommit = isStashCommit ? nil : [self.commitCache objectForKey:commitData.sha];
						if (cachedCommit) {
							newCommit = cachedCommit;
						} else {
							@try {
								newCommit = [[PBGitCommit alloc] initWithRepository:pbRepo andCommitData:commitData];
								if (!isStashCommit) {
									[self.commitCache setObject:newCommit forKey:commitData.sha];
								}
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
		}
	}
	
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
