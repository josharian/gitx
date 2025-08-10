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
		// Light blue for all non-selected search results
		NSColor *highlightColor = [NSColor colorWithCalibratedRed:0.751f green:0.831f blue:0.943f alpha:0.800f];
		[highlightColor set];
		
		NSRect highlightRect = NSInsetRect(dirtyRect, 1.0f, 1.0f);
		float radius = highlightRect.size.height / 2.0f;
		NSBezierPath *highlightPath = [NSBezierPath bezierPathWithRoundedRect:highlightRect xRadius:radius yRadius:radius];
		[highlightPath fill];
		
		// Draw subtle stroke
		NSColor *strokeColor = [NSColor colorWithCalibratedWhite:0.0f alpha:0.05f];
		[strokeColor set];
		[highlightPath stroke];
	}
}

- (void)drawSelectionInRect:(NSRect)dirtyRect
{
	if (self.isSearchResult && self.isSelected) {
		// Use system selection color for selected search results
		if ([[self window] isKeyWindow]) {
			if ([[self window] firstResponder] == self.superview) {
				[[NSColor alternateSelectedControlColor] set];
			} else {
				[[NSColor selectedControlColor] set];
			}
		} else {
			[[NSColor secondarySelectedControlColor] set];
		}
		
		NSRect highlightRect = NSInsetRect(dirtyRect, 1.0f, 1.0f);
		float radius = highlightRect.size.height / 2.0f;
		NSBezierPath *highlightPath = [NSBezierPath bezierPathWithRoundedRect:highlightRect xRadius:radius yRadius:radius];
		[highlightPath fill];
		
		// Draw darker stroke for selected
		NSColor *strokeColor = [NSColor colorWithCalibratedWhite:0.0f alpha:0.30f];
		[strokeColor set];
		[highlightPath stroke];
	} else {
		// Normal selection
		[super drawSelectionInRect:dirtyRect];
	}
}

@end