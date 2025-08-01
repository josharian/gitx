//
//  GitRepoFinder.m
//  GitX
//
//  Created by Rowan James on 13/11/2012.
//
//

#import "GitRepoFinder.h"

@implementation GitRepoFinder

+ (NSURL*)workDirForURL:(NSURL*)fileURL;
{
	if (!fileURL.isFileURL)
	{
		return nil;
	}
	
	// REPLACE WITH GIT EXEC - Use git rev-parse --show-toplevel instead of libgit2
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/usr/bin/git";
	task.arguments = @[@"rev-parse", @"--show-toplevel"];
	task.currentDirectoryPath = fileURL.path;
	
	NSPipe *pipe = [NSPipe pipe];
	task.standardOutput = pipe;
	task.standardError = [NSPipe pipe];
	
	@try {
		[task launch];
		[task waitUntilExit];
		
		if (task.terminationStatus == 0) {
			NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
			NSString *workdir = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			workdir = [workdir stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			
			if (workdir.length > 0) {
				return [NSURL fileURLWithPath:workdir];
			}
		}
	}
	@catch (NSException *exception) {
		// Git not found or other error
	}
	
	return nil;
}

+ (NSURL *)gitDirForURL:(NSURL *)fileURL
{
	if (!fileURL.isFileURL)
	{
		return nil;
	}
	
	// REPLACE WITH GIT EXEC - Use git rev-parse --git-dir instead of libgit2
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/usr/bin/git";
	task.arguments = @[@"rev-parse", @"--git-dir"];
	task.currentDirectoryPath = fileURL.path;
	
	NSPipe *pipe = [NSPipe pipe];
	task.standardOutput = pipe;
	task.standardError = [NSPipe pipe];
	
	@try {
		[task launch];
		[task waitUntilExit];
		
		if (task.terminationStatus == 0) {
			NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
			NSString *gitDir = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
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
	}
	@catch (NSException *exception) {
		// Git not found or other error
	}
	
	return nil;
}

@end