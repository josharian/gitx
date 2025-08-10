//
//  PBCommitListRowView.m
//  GitX
//
//  Custom row view for commit list that handles search highlighting
//

#import "PBCommitListRowView.h"

@implementation PBCommitListRowView

- (void)drawBackgroundInRect:(NSRect)dirtyRect
{
	// First draw the standard background (handles zebra striping and selection)
	[super drawBackgroundInRect:dirtyRect];
	
	// Then overlay search result highlighting if needed
	if (self.isSearchResult && !self.isSelected) {
		NSColor *highlightColor;
		if (self.isCurrentSearchResult) {
			// Current search result - medium blue
			highlightColor = [NSColor colorWithCalibratedRed:0.651f green:0.731f blue:0.843f alpha:0.900f];
		} else {
			// Other search results - light blue
			highlightColor = [NSColor colorWithCalibratedRed:0.751f green:0.831f blue:0.943f alpha:0.800f];
		}
		
		[highlightColor set];
		NSRectFillUsingOperation(dirtyRect, NSCompositingOperationSourceOver);
	}
}

- (void)drawSelectionInRect:(NSRect)dirtyRect
{
	if (self.isSearchResult && self.isSelected) {
		// Selected search result - medium blue
		NSColor *selectionColor = [NSColor colorWithCalibratedRed:0.651f green:0.731f blue:0.843f alpha:0.900f];
		[selectionColor set];
		NSRectFill(dirtyRect);
	} else {
		// Normal selection
		[super drawSelectionInRect:dirtyRect];
	}
}

@end