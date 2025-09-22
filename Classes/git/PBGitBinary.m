//
//  PBGitBinary.m
//  GitX
//
//  Created by Pieter de Bie on 04-10-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitBinary.h"
#import "PBEasyPipe.h"

@implementation PBGitBinary

static NSString *gitPath = nil;
static NSError *gitPathError = nil;
static NSString *cachedUserConfiguredPath = nil;

static NSString * const PBGitBinaryErrorDomain = @"PBGitBinaryErrorDomain";
static const NSInteger PBGitBinaryErrorNotFound = 1;

static dispatch_queue_t PBGitBinaryResolutionQueue(void)
{
	static dispatch_once_t onceToken;
	static dispatch_queue_t queue;
	dispatch_once(&onceToken, ^{
		queue = dispatch_queue_create("xyz.commaok.gitx.git-binary", DISPATCH_QUEUE_SERIAL);
	});
	return queue;
}

static NSString *PBGitBinarySanitizedPath(NSString *candidate)
{
	if (candidate.length == 0)
		return nil;

	NSString *trimmed = [candidate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (trimmed.length == 0)
		return nil;

	return [trimmed stringByStandardizingPath];
}

static NSString *PBGitBinaryValidatedExecutableAtPath(NSString *candidate)
{
	NSString *standardized = PBGitBinarySanitizedPath(candidate);
	if (standardized.length == 0)
		return nil;

	if (![[NSFileManager defaultManager] isExecutableFileAtPath:standardized])
		return nil;

	NSString *version = [PBGitBinary versionForPath:standardized];
	if (!version)
		return nil;

	return standardized;
}

static NSString *PBGitBinaryLocateGit(NSError * __autoreleasing *error)
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *userConfigured = [defaults stringForKey:@"gitExecutable"];
	NSString *resolved = PBGitBinaryValidatedExecutableAtPath(userConfigured);
	if (resolved)
		return resolved;

	if (userConfigured.length > 0)
		NSLog(@"PBGitBinary: user-configured git path '%@' is invalid; falling back to search paths.", userConfigured);

	char *envPath = getenv("GIT_PATH");
	if (envPath) {
		NSString *envCandidate = [NSString stringWithUTF8String:envPath];
		resolved = PBGitBinaryValidatedExecutableAtPath(envCandidate);
		if (resolved)
			return resolved;
	}

	NSString *whichPath = [PBEasyPipe outputForCommand:@"/usr/bin/which" withArgs:@[@"git"]];
	resolved = PBGitBinaryValidatedExecutableAtPath(whichPath);
	if (resolved)
		return resolved;

	for (NSString *location in [PBGitBinary searchLocations]) {
		resolved = PBGitBinaryValidatedExecutableAtPath(location);
		if (resolved)
			return resolved;
	}

	NSString *xcrunPath = [PBEasyPipe outputForCommand:@"/usr/bin/xcrun" withArgs:@[@"-f", @"git"]];
	resolved = PBGitBinaryValidatedExecutableAtPath(xcrunPath);
	if (resolved)
		return resolved;

	if (error) {
		NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: @"Could not locate git executable.",
			NSLocalizedRecoverySuggestionErrorKey: [PBGitBinary notFoundError] };
		*error = [NSError errorWithDomain:PBGitBinaryErrorDomain code:PBGitBinaryErrorNotFound userInfo:userInfo];
	}

	NSLog(@"PBGitBinary: Could not find a git binary. Checked user defaults, environment, PATH, standard locations, and xcrun.");
	return nil;
}

+ (NSString *)versionForPath:(NSString *)path
{
	NSString *standardized = PBGitBinarySanitizedPath(path);
	if (standardized.length == 0)
		return nil;

	if (![[NSFileManager defaultManager] isExecutableFileAtPath:standardized])
		return nil;

	NSString *version = [PBEasyPipe outputForCommand:standardized withArgs:@[@"--version"]];
	version = [version stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([version hasPrefix:@"git version "])
		return [version substringFromIndex:12];

	return nil;
}

+ (NSString *)path
{
	return [self resolveGitPath:nil];
}

+ (NSString *)resolveGitPath:(NSError * __autoreleasing *)error
{
	__block NSString *resolvedPath = nil;
	__block NSError *resolvedError = nil;

	dispatch_sync(PBGitBinaryResolutionQueue(), ^{
		NSString *currentUserSetting = [[NSUserDefaults standardUserDefaults] stringForKey:@"gitExecutable"];
		if ((cachedUserConfiguredPath || currentUserSetting) && ![cachedUserConfiguredPath isEqualToString:currentUserSetting]) {
			gitPath = nil;
			gitPathError = nil;
		}
		cachedUserConfiguredPath = [currentUserSetting copy];

		if (!gitPath && !gitPathError) {
			NSError *localError = nil;
			NSString *resolved = PBGitBinaryLocateGit(&localError);
			gitPath = resolved;
			gitPathError = localError;
		}

		resolvedPath = gitPath;
		resolvedError = gitPathError;
	});

	if (!resolvedPath && error)
		*error = resolvedError;

	return resolvedPath;
}

+ (void)invalidateCachedPath
{
	dispatch_sync(PBGitBinaryResolutionQueue(), ^{
		gitPath = nil;
		gitPathError = nil;
		cachedUserConfiguredPath = nil;
	});
}

static NSMutableArray *locations = nil;

+ (NSArray *)searchLocations
{
	if (!locations)
	{
		locations = [[NSMutableArray alloc] initWithObjects:
					 @"/opt/local/bin/git",
					 @"/sw/bin/git",
					 @"/opt/git/bin/git",
					 @"/usr/local/bin/git",
					 @"/usr/local/git/bin/git",
					 @"/opt/homebrew/bin/git",
					 nil];
		
		[locations addObject:[@"~/bin/git" stringByExpandingTildeInPath]];
		[locations addObject:@"/usr/bin/git"];
	}
	return locations;
}

+ (NSString *)notFoundError
{
	NSMutableString *error = [NSMutableString stringWithString:
							  @"Could not find a git binary.\n"
							  @"Please make sure there is a git binary in one of the following locations:\n\n"];
	for (NSString *location in [PBGitBinary searchLocations]) {
		[error appendFormat:@"\t%@\n", location];
	}
	return error;
}


+ (NSString *)version
{
	NSString *path = [self resolveGitPath:nil];
	if (!path)
		return nil;

	return [self versionForPath:path];
}


@end
