//
//  PBCommitList.m
//  GitX
//
//  Created by Pieter de Bie on 9/11/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBCommitList.h"
#import "PBGitRevisionCell.h"
#import "PBWebHistoryController.h"
#import "PBHistorySearchController.h"
@implementation PBCommitList

#pragma mark Row highlighting

- (NSColor *)searchResultHighlightColorForRow:(NSInteger)rowIndex
{
	// if the row is selected use default colors
	if ([self isRowSelected:rowIndex]) {
		if ([[self window] isKeyWindow]) {
			if ([[self window] firstResponder] == self) {
				return [NSColor alternateSelectedControlColor];
			}
			return [NSColor selectedControlColor];
		}
		return [NSColor secondarySelectedControlColor];
	}

	// light blue color highlighting search results
	return [NSColor colorWithCalibratedRed:0.751f green:0.831f blue:0.943f alpha:0.800f];
}

- (NSColor *)searchResultHighlightStrokeColorForRow:(NSInteger)rowIndex
{
	if ([self isRowSelected:rowIndex])
		return [NSColor colorWithCalibratedWhite:0.0f alpha:0.30f];

	return [NSColor colorWithCalibratedWhite:0.0f alpha:0.05f];
}

- (void)drawRow:(NSInteger)rowIndex clipRect:(NSRect)tableViewClipRect
{
	NSRect rowRect = [self rectOfRow:rowIndex];
	BOOL isRowVisible = NSIntersectsRect(rowRect, tableViewClipRect);

	// draw special highlighting if the row is part of search results
	if (isRowVisible && [searchController isRowInSearchResults:rowIndex]) {
		NSRect highlightRect = NSInsetRect(rowRect, 1.0f, 1.0f);
		float radius = highlightRect.size.height / 2.0f;

		NSBezierPath *highlightPath = [NSBezierPath bezierPathWithRoundedRect:highlightRect xRadius:radius yRadius:radius];

		[[self searchResultHighlightColorForRow:rowIndex] set];
		[highlightPath fill];

		[[self searchResultHighlightStrokeColorForRow:rowIndex] set];
		[highlightPath stroke];
	}

	// draws the content inside the row
	[super drawRow:rowIndex clipRect:tableViewClipRect];
}

- (void)highlightSelectionInClipRect:(NSRect)tableViewClipRect
{
	// disable highlighting if the selected row is part of search results
	// instead do the highlighting in drawRow:clipRect: above
	if ([searchController isRowInSearchResults:[self selectedRow]])
		return;

	[super highlightSelectionInClipRect:tableViewClipRect];
}


- (IBAction)performFindPanelAction:(id)sender
{
	PBFindPanelActionBlock block = self.findPanelActionBlock;
	if (block) {
		block(sender);
	}
}

@end
