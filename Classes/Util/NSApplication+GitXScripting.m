//
//  NSApplication+GitXScripting.m
//  GitX
//
//  Created by Nathan Kinsinger on 8/15/10.
//  Copyright 2010 Nathan Kinsinger. All rights reserved.
//

#import "NSApplication+GitXScripting.h"
#import "GitXScriptingConstants.h"
#import "PBDiffWindowController.h"
#import "PBGitRepository.h"
#import "PBCloneRepositoryPanel.h"

// REPLACE WITH GIT EXEC - Removed ObjectiveGit dependency
// #import <ObjectiveGit/GTRepository.h>


@implementation NSApplication (GitXScripting)

- (void)showDiffScriptCommand:(NSScriptCommand *)command
{
	NSString *diffText = [command directParameter];
	if (diffText) {
		PBDiffWindowController *diffController = [[PBDiffWindowController alloc] initWithDiff:diffText];
		[diffController showWindow:nil];
		[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
	}
}

- (void)initRepositoryScriptCommand:(NSScriptCommand *)command
{
	NSURL *repositoryURL = [command directParameter];
	if (!repositoryURL)
        return;

    // Initialize empty repository using git init
    NSTask *gitTask = [[NSTask alloc] init];
    gitTask.launchPath = @"/usr/bin/git";
    gitTask.arguments = @[@"init"];
    gitTask.currentDirectoryPath = [repositoryURL path];
    
    NSPipe *errorPipe = [NSPipe pipe];
    gitTask.standardError = errorPipe;
    
    BOOL success = NO;
    @try {
        [gitTask launch];
        [gitTask waitUntilExit];
        
        if (gitTask.terminationStatus == 0) {
            success = YES;
        } else {
            NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
            NSString *errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
            NSLog(@"Failed to create repository at %@: %@", repositoryURL, errorOutput);
            return;
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Failed to create repository at %@: %@", repositoryURL, exception.reason);
        return;
    }

    [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:repositoryURL
                                                                           display:YES
                                                                 completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error) {
                                                                     if (error) {
                                                                         NSLog(@"Failed to open repository at %@: %@", repositoryURL, error);
                                                                     }
                                                                 }];
}

- (void)cloneRepositoryScriptCommand:(NSScriptCommand *)command
{
	NSString *repository = [command directParameter];
	if (repository) {
		NSDictionary *arguments = [command arguments];
		NSURL *destinationURL = [arguments objectForKey:kGitXCloneDestinationURLKey];
		if (destinationURL) {
			BOOL isBare = [[arguments objectForKey:kGitXCloneIsBareKey] boolValue];

			[PBCloneRepositoryPanel beginCloneRepository:repository toURL:destinationURL isBare:isBare];
		}
	}
}

@end
