//
//  PBCreateBranchSheet.h
//  GitX
//
//  Created by Nathan Kinsinger on 12/13/09.
//  Copyright 2009 Nathan Kinsinger. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PBGitRefish.h"


@class PBGitRepository;
@class PBGitWindowController;


@interface PBCreateBranchSheet : NSWindowController

+ (void) beginCreateBranchSheetAtRefish:(id <PBGitRefish>)ref inRepository:(PBGitRepository *)repo;


- (IBAction) createBranch:(id)sender;
- (IBAction) closeCreateBranchSheet:(id)sender;


@property (nonatomic, strong) PBGitRepository *repository;
@property (nonatomic, strong) PBGitWindowController *repoWindow;
@property (nonatomic, strong) id <PBGitRefish> startRefish;
@property (nonatomic, assign) BOOL shouldCheckoutBranch;

@property (nonatomic, assign) IBOutlet NSTextField *branchNameField;
@property (nonatomic, assign) IBOutlet NSTextField *errorMessageField;

@end
