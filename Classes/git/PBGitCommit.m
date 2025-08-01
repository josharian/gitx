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

@interface GTSignature : NSObject
@property (nonatomic, strong) NSString *name;
@end

@interface GTCommit : NSObject  
@property (nonatomic, strong) NSDate *commitDate;
@property (nonatomic, strong) NSString *messageSummary;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, strong) GTSignature *author;
@property (nonatomic, strong) GTSignature *committer;
@property (nonatomic, strong) NSArray *parents;
@property (nonatomic, strong) GTOID *OID;
@property (nonatomic, strong) NSString *SHA;
@property (nonatomic, strong) NSString *shortSHA;
@end

@implementation GTSignature
@end

@implementation GTCommit  
@end

NSString * const kGitXCommitType = @"commit";

@interface PBGitCommit ()

@property (nonatomic, weak) PBGitRepository *repository;
@property (nonatomic, strong) GTCommit *gtCommit;
@property (nonatomic, strong) NSArray *parents;

@property (nonatomic, strong) NSString *patch;
@property (nonatomic, strong) GTOID *sha;

@end


@implementation PBGitCommit

- (NSDate *) date
{
	return self.gtCommit.commitDate;
	// previous behaviour was equiv. to:  return self.gtCommit.author.time;
}

- (NSString *) dateString
{
	NSDateFormatter* formatter = [[NSDateFormatter alloc] initWithDateFormat:@"%Y-%m-%d %H:%M:%S" allowNaturalLanguage:NO];
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
	NSTask *gitTask = [[NSTask alloc] init];
	gitTask.launchPath = @"/usr/bin/git";
	gitTask.arguments = @[@"show", @"--format=%H%n%s%n%B%n%an%n%cn%n%ct%n%P", @"--no-patch", sha];
	gitTask.currentDirectoryPath = [repo.fileURL path];
	
	NSPipe *outputPipe = [NSPipe pipe];
	gitTask.standardOutput = outputPipe;
	gitTask.standardError = [NSPipe pipe];
	
	GTCommit *commit = [[GTCommit alloc] init];
	
	@try {
		[gitTask launch];
		[gitTask waitUntilExit];
		
		if (gitTask.terminationStatus == 0) {
			NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
			NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
			NSArray *lines = [output componentsSeparatedByString:@"\n"];
			
			if (lines.count >= 7) {
				NSString *shaString = lines[0];
				commit.SHA = shaString;
				commit.shortSHA = [shaString substringToIndex:MIN(7, [shaString length])];
				commit.messageSummary = lines[1];
				commit.message = lines[2];
				
				GTSignature *author = [[GTSignature alloc] init];
				author.name = lines[3];
				commit.author = author;
				
				GTSignature *committer = [[GTSignature alloc] init];
				committer.name = lines[4];
				commit.committer = committer;
				
				NSTimeInterval timestamp = [lines[5] doubleValue];
				commit.commitDate = [NSDate dateWithTimeIntervalSince1970:timestamp];
				
				// Parse parent commit SHAs
				NSString *parentSHAsString = lines[6];
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
			}
		}
	}
	@catch (NSException *exception) {
		// Fall back to empty commit on error
	}
	
	self.gtCommit = commit;
	
	return self;
}


- (NSArray *)parents
{
	if (!self->_parents) {
		NSArray *gtParents = self.gtCommit.parents;
		NSMutableArray *parents = [NSMutableArray arrayWithCapacity:gtParents.count];
		for (GTCommit *parent in gtParents) {
			[parents addObject:parent.OID];
		}
		self.parents = parents;
	}
	return self->_parents;
}

- (NSString *)subject
{
	return self.gtCommit.messageSummary;
}

- (NSString *)author
{
	NSString *result = self.gtCommit.author.name;
	return result;
}

- (NSString *)committer
{
	GTSignature *sig = self.gtCommit.committer;
	return sig.name;
}

- (NSString *)SVNRevision
{
	NSString *result = nil;
	if ([self.repository hasSVNRemote])
	{
		// get the git-svn-id from the message
		NSArray *matches = nil;
		NSString *string = self.gtCommit.message;
		NSError *error = nil;
		// Regular expression for pulling out the SVN revision from the git log
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^git-svn-id: .*@(\\d+) .*$" options:NSRegularExpressionAnchorsMatchLines error:&error];
		
		if (string) {
			matches = [regex matchesInString:string options:0 range:NSMakeRange(0, [string length])];
			for (NSTextCheckingResult *match in matches)
			{
				NSRange matchRange = [match rangeAtIndex:1];
				NSString *matchString = [string substringWithRange:matchRange];
				result = matchString;
			}
		}
	}
	return result;
}

- (GTOID *)sha
{
	GTOID *result = _sha;
	if (result) {
		return result;
	}
    result = self.gtCommit.OID;
	_sha = result;
	return result;
}

- (NSString *)realSha
{
	return self.gtCommit.SHA;
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

	NSString *p = [self.repository outputForArguments:[NSArray arrayWithObjects:@"format-patch",  @"-1", @"--stdout", [self realSha], nil]];
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
	return self.gtCommit.shortSHA;
}

- (NSString *) refishType
{
	return kGitXCommitType;
}

@end
