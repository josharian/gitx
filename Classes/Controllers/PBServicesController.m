//
//  PBServicesController.m
//  GitX
//
//  Created by Pieter de Bie on 10/24/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBServicesController.h"
#import "PBGitRepository.h"

@implementation PBServicesController

- (NSString *)completeSHA1For:(NSString *)sha
{
	NSArray *documents = [[NSApplication sharedApplication] orderedDocuments];
	for (PBGitRepository *repo in documents)
	{
		NSError *error = nil;
		NSString *s = [repo executeGitCommand:[NSArray arrayWithObjects:@"log", @"-1", @"--pretty=format:%h (%s)", sha, nil] error:&error];
		if (!error)
			return s;
	}
	return @"Could not find SHA";
}

-(NSString *)runNameRevFor:(NSString *)s
{
	NSArray *repositories = [[NSApplication sharedApplication] orderedDocuments];
	if ([repositories count] == 0)
		return s;
	PBGitRepository *repo = [repositories objectAtIndex:0];
	NSError *error = nil;
	NSString *returnString = [repo executeGitCommand:[NSArray arrayWithObjects:@"name-rev", @"--stdin", nil] withInput:s error:&error];
	if (error)
		return s;
	return returnString;
}

-(void)completeSha:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error
{
	NSArray *types = [pboard types];
	if (![types containsObject:NSStringPboardType])
	{
		*error = @"Could not get data";
		return;
	}

	NSString *s = [pboard stringForType:NSStringPboardType];
	if ([s rangeOfString:@" "].location == NSNotFound)
		s = [self completeSHA1For:s];
	else
		s = [self runNameRevFor:s];

	[pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
	[pboard setString:s forType:NSStringPboardType];
}
@end
