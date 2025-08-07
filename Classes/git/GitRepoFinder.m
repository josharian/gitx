//
//  GitRepoFinder.m
//  GitX
//
//  Created by Rowan James on 13/11/2012.
//
//

#import "GitRepoFinder.h"
#import "PBGitBinary.h"
#import "PBEasyPipe.h"

@implementation GitRepoFinder

+ (NSURL*)workDirForURL:(NSURL*)fileURL;
{
	if (!fileURL.isFileURL)
	{
		return nil;
	}
	
	NSString *gitPath = [PBGitBinary path];
	if (!gitPath) {
		gitPath = @"/usr/bin/git"; // Fallback
	}
	
	int exitCode = 0;
	NSString *workdir = [PBEasyPipe outputForCommand:gitPath
	                                        withArgs:@[@"rev-parse", @"--show-toplevel"]
	                                           inDir:fileURL.path
	                                        retValue:&exitCode];
	
	if (exitCode == 0 && workdir.length > 0) {
		workdir = [workdir stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (workdir.length > 0) {
			return [NSURL fileURLWithPath:workdir];
		}
	}
	
	return nil;
}

+ (NSURL *)gitDirForURL:(NSURL *)fileURL
{
	if (!fileURL.isFileURL)
	{
		return nil;
	}
	
	NSString *gitPath = [PBGitBinary path];
	if (!gitPath) {
		gitPath = @"/usr/bin/git"; // Fallback
	}
	
	int exitCode = 0;
	NSString *gitDir = [PBEasyPipe outputForCommand:gitPath
	                                       withArgs:@[@"rev-parse", @"--git-dir"]
	                                          inDir:fileURL.path
	                                       retValue:&exitCode];
	
	if (exitCode == 0 && gitDir.length > 0) {
		gitDir = [gitDir stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		if (gitDir.length > 0) {
			// Handle relative paths
			if (![gitDir hasPrefix:@"/"]) {
				gitDir = [[fileURL.path stringByAppendingPathComponent:gitDir] stringByStandardizingPath];
			}
			
			BOOL isDirectory;
			if ([[NSFileManager defaultManager] fileExistsAtPath:gitDir isDirectory:&isDirectory] && isDirectory) {
				return [NSURL fileURLWithPath:gitDir isDirectory:YES];
			}
		}
	}
	
	return nil;
}

@end