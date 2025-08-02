//
//  GitTest_AppDelegate.m
//  GitTest
//
//  Created by Pieter de Bie on 13-06-08.
//  Copyright __MyCompanyName__ 2008 . All rights reserved.
//

#import "ApplicationController.h"
#import "PBGitRevisionCell.h"
#import "PBGitWindowController.h"
#import "PBServicesController.h"
#import "PBGitXProtocol.h"
#import "PBPrefsWindowController.h"
#import "PBNSURLPathUserDefaultsTransfomer.h"
#import "PBGitDefaults.h"
#import "OpenRecentController.h"
#import "PBGitBinary.h"


static OpenRecentController* recentsDialog = nil;

@implementation ApplicationController

- (ApplicationController*)init
{
#ifdef DEBUG_BUILD
	[NSApp activateIgnoringOtherApps:YES];
#endif

	if(!(self = [super init]))
		return nil;

	if(![[NSBundle bundleWithPath:@"/System/Library/Frameworks/Quartz.framework/Frameworks/QuickLookUI.framework"] load])
		if(![[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/QuickLookUI.framework"] load])
			NSLog(@"Could not load QuickLook");

	/* Value Transformers */
	NSValueTransformer *transformer = [[PBNSURLPathUserDefaultsTransfomer alloc] init];
	[NSValueTransformer setValueTransformer:transformer forName:@"PBNSURLPathUserDefaultsTransfomer"];
	
	// Make sure the PBGitDefaults is initialized, by calling a random method
	[PBGitDefaults class];
	
	started = NO;
	return self;
}

- (void)registerServices
{
	// Register URL
	[NSURLProtocol registerClass:[PBGitXProtocol class]];

	// Register the service class
	PBServicesController *services = [[PBServicesController alloc] init];
	[NSApp setServicesProvider:services];

	// Force update the services menu if we have a new services version
	NSInteger serviceVersion = [[NSUserDefaults standardUserDefaults] integerForKey:@"Services Version"];
	if (serviceVersion < 2)
	{
		NSLog(@"Updating services menu…");
		NSUpdateDynamicServices();
		[[NSUserDefaults standardUserDefaults] setInteger:2 forKey:@"Services Version"];
	}
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
	if(!started || [[[NSDocumentController sharedDocumentController] documents] count])
		return NO;
	return YES;
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)theApplication
{
	recentsDialog = [[OpenRecentController alloc] init];
	if ([recentsDialog.possibleResults count] > 0)
	{
		[recentsDialog show];
		return YES;
	}
	else
	{
		return NO;
	}
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification
{


	[self registerServices];
	started = YES;
}

- (void) windowWillClose: sender
{
	[firstResponder terminate: sender];
}

- (IBAction)openPreferencesWindow:(id)sender
{
	[[PBPrefsWindowController sharedPrefsWindowController] showWindow:nil];
}

- (IBAction)showAboutPanel:(id)sender
{
	NSString *gitversion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleGitVersion"];
	NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
	if (gitversion)
		[dict addEntriesFromDictionary:[[NSDictionary alloc] initWithObjectsAndKeys:gitversion, @"Version", nil]];

	#ifdef DEBUG_BUILD
		[dict addEntriesFromDictionary:[[NSDictionary alloc] initWithObjectsAndKeys:@"GitX-dev (DEBUG)", @"ApplicationName", nil]];
	#endif

	[dict addEntriesFromDictionary:[[NSDictionary alloc] initWithObjectsAndKeys:@"GitX-dev (rowanj fork)", @"ApplicationName", nil]];

	[NSApp orderFrontStandardAboutPanelWithOptions:dict];
}




#pragma mark Help menu

- (IBAction)showHelp:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://rowanj.github.io/gitx/"]];
}

- (IBAction)reportAProblem:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/rowanj/gitx/issues"]];
}

- (IBAction)showChangeLog:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://builds.phere.net/GitX/development/GitX-dev.html"]];
}



@end
