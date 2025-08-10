//
//  PBCreateTagSheet.h
//  GitX
//
//  Created by Nathan Kinsinger on 12/18/09.
//  Copyright 2009 Nathan Kinsinger. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "PBGitRefish.h"

@class PBGitRepository;
@class PBGitWindowController;


@interface PBCreateTagSheet : NSWindowController
{
}

+ (void) beginCreateTagSheetAtRefish:(id <PBGitRefish>)refish inRepository:(PBGitRepository *)repo;

- (IBAction) createTag:(id)sender;
- (IBAction) closeCreateTagSheet:(id)sender;

@property (nonatomic, strong) PBGitRepository *repository;
@property (nonatomic, strong) PBGitWindowController *repoWindow;
@property (nonatomic, strong) id <PBGitRefish> targetRefish;

@property (nonatomic, weak) IBOutlet NSTextField *tagNameField;
@property (nonatomic, strong) IBOutlet NSTextView  *tagMessageText;
@property (nonatomic, weak) IBOutlet NSTextField *errorMessageField;

@end
