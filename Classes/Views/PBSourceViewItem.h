//
//  PBSourceViewItem.h
//  GitX
//
//  Created by Pieter de Bie on 9/8/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PBGitRevSpecifier;
@class PBGitRef;

@interface PBSourceViewItem : NSObject {
    NSMutableOrderedSet *childrenSet;

	NSString *title;
	PBGitRevSpecifier *revSpecifier;

	BOOL isGroupItem;
	BOOL isUncollapsible;
}

+ (id)groupItemWithTitle:(NSString *)title;
+ (id)itemWithRevSpec:(PBGitRevSpecifier *)revSpecifier;
+ (id)itemWithTitle:(NSString *)title;

- (void)addChild:(PBSourceViewItem *)child;
- (void)removeChild:(PBSourceViewItem *)child;
- (NSImage*)iconNamed:(NSString*)name;

// This adds the ref to the path, which should match the item's title,
// so "refs/heads/pu/pb/sidebar" would have the path [@"pu", @"pb", @"sidebare"]
// to the 'local' branch thing
- (void)addRev:(PBGitRevSpecifier *)revSpecifier toPath:(NSArray *)path;
- (PBSourceViewItem *)findRev:(PBGitRevSpecifier *)rev;

- (PBGitRef *) ref;

@property (nonatomic, copy) NSString *title;
@property (nonatomic, readonly) NSArray *sortedChildren;
@property (nonatomic, assign) BOOL isGroupItem, isUncollapsible, isExpanded;
@property (nonatomic, strong) PBGitRevSpecifier *revSpecifier;
@property (nonatomic, weak) PBSourceViewItem *parent;
@property (nonatomic, readonly) NSString *iconName;
@property (nonatomic, readonly) NSImage *icon;

@end
