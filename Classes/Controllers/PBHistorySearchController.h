//
//  PBHistorySearchController.h
//  GitX
//
//  Created by Nathan Kinsinger on 8/21/10.
//  Copyright 2010 Nathan Kinsinger. All rights reserved.
//

#import <Cocoa/Cocoa.h>


typedef NS_ENUM(NSInteger, PBHistorySearchMode) {
    PBHistorySearchModeBasic = 1,
    PBHistorySearchModePickaxe,
    PBHistorySearchModeRegex,
    PBHistorySearchModePath,
    PBHistorySearchModeMax    // always keep this item last
};

@class PBGitHistoryController;


@interface PBHistorySearchController : NSObject {
	PBHistorySearchMode searchMode;
	NSIndexSet *results;
	NSTimer *searchTimer;
	NSTask *backgroundSearchTask;
	NSPanel *rewindPanel;
}

@property (nonatomic, weak) IBOutlet PBGitHistoryController *historyController;
@property (nonatomic, weak) IBOutlet NSArrayController *commitController;

@property (nonatomic, weak) IBOutlet NSSearchField *searchField;
@property (nonatomic, weak) IBOutlet NSSegmentedControl *stepper;
@property (nonatomic, weak) IBOutlet NSTextField *numberOfMatchesField;
@property (nonatomic, weak) IBOutlet NSProgressIndicator *progressIndicator;

@property PBHistorySearchMode searchMode;


- (BOOL)isRowInSearchResults:(NSInteger)rowIndex;
- (BOOL)hasSearchResults;

- (void)selectSearchMode:(id)sender;

- (void)selectNextResult;
- (void)selectPreviousResult;
- (IBAction)stepperPressed:(id)sender;

- (void)clearSearch;
- (IBAction)updateSearch:(id)sender;

- (void)setHistorySearch:(NSString *)searchString mode:(NSInteger)mode;

@end
