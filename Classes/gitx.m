//
//  gitx.m
//  GitX
//
//  Created by Ciarán Walsh on 15/08/2008.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitBinary.h"
#import "GitXScriptingConstants.h"
#import "GitX-Swift.h"


#pragma mark Commands handled locally

void usage(char const *programName)
{
	printf("Usage: %s (--help|--version|--git-path)\n", programName);
	printf("   or: %s [<path>]\n", programName);
	printf("\n");
	printf("    -h, --help             print this help\n");
	printf("    -v, --version          prints version info for both GitX and git\n");
	printf("    --git-path             prints the path to the directory containing git\n");
	printf("\n");
	printf("Repository path\n");
	printf("    By default gitx opens the repository in the current directory.\n");
	printf("    To open a repository somewhere else, provide the path as an argument.\n");
	printf("\n");
	printf("    <path>                 open the repository located at <path>\n");
	printf("\n");
	exit(1);
}

void version_info()
{
	NSString *version = [[[NSBundle bundleForClass:[PBGitBinary class]] infoDictionary] valueForKey:@"CFBundleVersion"];
	NSString *gitVersion = [[[NSBundle bundleForClass:[PBGitBinary class]] infoDictionary] valueForKey:@"CFBundleGitVersion"];
	printf("GitX version %s (%s)\n", [version UTF8String], [gitVersion UTF8String]);
	if ([PBGitBinary path])
		printf("Using git found at %s, version %s\n", [[PBGitBinary path] UTF8String], [[PBGitBinary version] UTF8String]);
	else
		printf("GitX cannot find a git binary\n");
	exit(1);
}

void git_path()
{
	if (![PBGitBinary path])
		exit(101);

	NSString *path = [[PBGitBinary path] stringByDeletingLastPathComponent];
	printf("%s\n", [path UTF8String]);
	exit(0);
}


#pragma mark -
#pragma mark Commands sent to GitX

void handleOpenRepository(NSURL *repositoryURL)
{
	// use NSWorkspace to open GitX
	BOOL didOpenURLs = [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:repositoryURL]
								   withAppBundleIdentifier:kGitXBundleIdentifier
												   options:0
							additionalEventParamDescriptor:nil
										 launchIdentifiers:NULL];
	if (!didOpenURLs) {
		printf("Unable to open GitX.app\n");
		exit(2);
	}
}


#pragma mark -
#pragma mark main


NSURL *workingDirectoryURL(NSMutableArray *arguments)
{
    // path to git repository has been explicitly passed as positional argument?
	if ([arguments count] && ![[arguments objectAtIndex:0] hasPrefix:@"-"]) {
		NSString *path = [[arguments objectAtIndex:0] stringByStandardizingPath];

		// the path must exist and point to a directory
		BOOL isDirectory = YES;
		if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
			if (!isDirectory)
				printf("Fatal: path does not point to a directory.\n");
			else
				printf("Fatal: path does not exist.\n");
			printf("Cannot open git repository at path: '%s'\n", [path UTF8String]);
			exit(2);
		}

		// remove the path argument
		[arguments removeObjectAtIndex:0];

        // create and return corresponding NSURL
        NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
        if (!url) {
            printf("Unable to create url to path: %s\n", [path UTF8String]);
            exit(2);
        }

        return url;
	}

    // otherwise, determine current working directory
    NSString *pwd = [[[NSProcessInfo processInfo] environment] objectForKey:@"PWD"];

	NSURL* pwdURL = [NSURL fileURLWithPath:pwd];
	NSURL* repoURL = [GitRepoFinder workDirForURL:pwdURL];
	return repoURL;

}

NSMutableArray *argumentsArray()
{
	NSMutableArray *arguments = [[[NSProcessInfo processInfo] arguments] mutableCopy];
	[arguments removeObjectAtIndex:0]; // url to executable path is not needed

	return arguments;
}

int main(int argc, const char** argv)
{
	@autoreleasepool {
		if (argc >= 2 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h")))
			usage(argv[0]);
		if (argc >= 2 && (!strcmp(argv[1], "--version") || !strcmp(argv[1], "-v")))
			version_info();
		if (argc >= 2 && !strcmp(argv[1], "--git-path"))
			git_path();
		
		// From here on everything needs to access git, so make sure it's installed
		if (![PBGitBinary path]) {
			printf("%s\n", [[PBGitBinary notFoundError] cStringUsingEncoding:NSUTF8StringEncoding]);
			exit(2);
		}
		
		// From this point, we require a working directory
		NSMutableArray *arguments = argumentsArray();
		NSURL *wdURL = workingDirectoryURL(arguments);
		if (!wdURL)
		{
			printf("Could not find a git working directory.\n");
			exit(0);
		}
		
		// Open the repository in GitX
		handleOpenRepository(wdURL);
		
		return 0;
	}
}