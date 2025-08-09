//
//  PBGitCommit.m
//  GitTest
//
//  Created by Pieter de Bie on 13-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitRepository.h"
#import "PBGitCommit.h"
#import "PBGitTree.h"
#import "PBGitRef.h"
#import "PBGitDefaults.h"
#import "PBCommitData.h"



NSString * const kGitXCommitType = @"commit";

@interface PBGitCommit ()

@property (nonatomic, weak) PBGitRepository *repository;
@property (nonatomic, strong) PBCommitData *commitData;
@property (nonatomic, strong) NSArray *parents;

@property (nonatomic, strong) NSString *patch;
@property (nonatomic, strong) NSString *sha;

@end


@implementation PBGitCommit

- (NSDate *) date
{
	return self.commitData.commitDate;
}

- (NSString *) dateString
{
	NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"%Y-%m-%d %H:%M:%S"];
	return [formatter stringFromDate: self.date];
}

- (NSArray*) treeContents
{
	return self.tree.children;
}

- (id)initWithRepository:(PBGitRepository *)repo andSHA:(NSString *)sha
{
	self = [super init];
	if (!self) {
		return nil;
	}
	self.repository = repo;
	
	// Use git show to populate commit data including parent SHAs
	NSError *error = nil;
	NSString *output = [repo executeGitCommand:@[@"show", @"--format=%H%n%s%n%B%n%an%n%cn%n%ct%n%P", @"--no-patch", sha] error:&error];
	
	PBCommitData *commitData = [[PBCommitData alloc] init];
	
	if (!error && output) {
		NSArray *lines = [output componentsSeparatedByString:@"\n"];
		
		if (lines.count >= 7) {
			NSString *shaString = lines[0];
			commitData.sha = shaString;
			commitData.shortSHA = [shaString substringToIndex:MIN(7, [shaString length])];
			commitData.messageSummary = lines[1];
			commitData.message = lines[2];
			commitData.authorName = lines[3];
			commitData.committerName = lines[4];
			
			NSTimeInterval timestamp = [lines[5] doubleValue];
			commitData.commitDate = [NSDate dateWithTimeIntervalSince1970:timestamp];
			
			// Parse parent commit SHAs - just store the SHA strings
			NSString *parentSHAsString = lines[6];
			NSMutableArray *parentSHAs = [NSMutableArray array];
			if ([parentSHAsString length] > 0) {
				NSArray *parentSHAsList = [parentSHAsString componentsSeparatedByString:@" "];
				for (NSString *parentSHA in parentSHAsList) {
					NSString *trimmedSHA = [parentSHA stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
					if ([trimmedSHA length] >= 40) {
						[parentSHAs addObject:trimmedSHA];
					}
				}
			}
			commitData.parentSHAs = parentSHAs;
		}
	}
	
	self.commitData = commitData;
	
	return self;
}

- (id)initWithRepository:(PBGitRepository *)repo andCommitData:(PBCommitData *)commitData
{
	self = [super init];
	if (!self) {
		return nil;
	}
	self.repository = repo;
	self.commitData = commitData;
	
	return self;
}


- (NSArray *)parents
{
	if (!self->_parents) {
		NSArray *parentSHAs = self.commitData.parentSHAs;
		NSMutableArray *parents = [NSMutableArray arrayWithCapacity:parentSHAs.count];
		for (NSString *parentSHA in parentSHAs) {
			[parents addObject:parentSHA];
		}
		self.parents = parents;
	}
	return self->_parents;
}

- (NSString *)subject
{
	return self.commitData.messageSummary;
}

- (NSString *)author
{
	return self.commitData.authorName;
}

- (NSString *)committer
{
	return self.commitData.committerName;
}


- (NSString *)sha
{
	NSString *result = _sha;
	if (result) {
		return result;
	}
    result = self.commitData.sha;
	_sha = result;
	return result;
}

- (NSString *)realSha
{
	return self.commitData.sha;
}

- (BOOL) isOnSameBranchAs:(PBGitCommit *)otherCommit
{
	if (!otherCommit)
		return NO;

	if ([self isEqual:otherCommit])
		return YES;

	return [self.repository isOnSameBranch:otherCommit.sha asSHA:self.sha];
}

- (BOOL) isOnHeadBranch
{
	return [self isOnSameBranchAs:[self.repository headCommit]];
}

- (BOOL)isEqual:(id)otherCommit
{
	if (self == otherCommit) {
		return YES;
	}
	return NO;
}

- (NSUInteger)hash
{
	return [self.sha hash];
}

// FIXME: Remove this method once it's unused.
- (NSString*) details
{
	return @"";
}

- (NSString *) patch
{
	if (self->_patch != nil)
		return _patch;

	NSError *error = nil;
	NSString *p = [self.repository executeGitCommand:[NSArray arrayWithObjects:@"format-patch",  @"-1", @"--stdout", [self realSha], nil] error:&error];
	// Add a GitX identifier to the patch ;)
	self.patch = [[p substringToIndex:[p length] -1] stringByAppendingString:@"+GitX"];
	return self->_patch;
}

- (PBGitTree*) tree
{
	return [PBGitTree rootForCommit: self];
}

- (void)addRef:(PBGitRef *)ref
{
	if (!self.refs)
		self.refs = [NSMutableArray arrayWithObject:ref];
	else
		[self.refs addObject:ref];
}

- (void)removeRef:(id)ref
{
	if (!self.refs)
		return;

	[self.refs removeObject:ref];
}

- (BOOL) hasRef:(PBGitRef *)ref
{
	if (!self.refs)
		return NO;

	for (PBGitRef *existingRef in self.refs)
		if ([existingRef isEqualToRef:ref])
			return YES;

	return NO;
}

- (NSMutableArray *)refs
{
	return self.repository.refs[self.sha];
}

- (void) setRefs:(NSMutableArray *)refs
{
	self.repository.refs[self.sha] = [NSMutableArray arrayWithArray:refs];
}


+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector
{
	return NO;
}

+ (BOOL)isKeyExcludedFromWebScript:(const char *)name {
	return NO;
}


#pragma mark <PBGitRefish>

- (NSString *) refishName
{
	return [self realSha];
}

- (NSString *) shortName
{
	return self.commitData.shortSHA;
}

- (NSString *) refishType
{
	return kGitXCommitType;
}

@end
