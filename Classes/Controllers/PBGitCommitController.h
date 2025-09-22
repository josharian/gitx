//
//  PBGitCommitController.h
//  GitX
//
//  Created by Pieter de Bie on 19-09-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PBViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class PBGitIndexController;
@class PBIconAndTextCell;
@class PBWebChangesController;
@class PBGitIndex;
@class PBNiceSplitView;
@class PBCommitMessageView;
@class PBChangedFile;

@interface PBGitCommitController : PBViewController {
	// This might have to transfer over to the PBGitRepository
	// object sometime
	PBGitIndex *index;

	IBOutlet PBCommitMessageView *commitMessageView;
	IBOutlet NSArrayController *unstagedFilesController;
	IBOutlet NSArrayController *cachedFilesController;
	IBOutlet NSButton *commitButton;

	IBOutlet PBGitIndexController *indexController;
	IBOutlet PBWebChangesController *webController;
	IBOutlet PBNiceSplitView *commitSplitView;
}

@property (readonly) PBGitIndex *index;

- (IBAction)refresh:(nullable id)sender;
- (IBAction)commit:(nullable id)sender;
- (IBAction)forceCommit:(nullable id)sender;
- (IBAction)signOff:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
