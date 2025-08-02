//
//  PBNiceSplitView.m
//  GitX
//
//  Created by Pieter de Bie on 31-10-08.
//  Copyright 2008 Pieter de Bie. All rights reserved.
//

#import "PBNiceSplitView.h"

static NSImage *bar;
static NSImage *grip;

@implementation PBNiceSplitView

+(void) initialize
{
	NSString *barPath = [[NSBundle mainBundle] pathForResource:@"mainSplitterBar" ofType:@"tiff"];
	bar = [[NSImage alloc] initWithContentsOfFile: barPath];
	if (!bar) {
		NSLog(@"Failed to load mainSplitterBar.tiff from path: %@", barPath);
	}

	NSString *gripPath = [[NSBundle mainBundle] pathForResource:@"mainSplitterDimple" ofType:@"tiff"];
	grip = [[NSImage alloc] initWithContentsOfFile: gripPath];
	if (!grip) {
		NSLog(@"Failed to load mainSplitterDimple.tiff from path: %@", gripPath);
	}
}

- (void)drawDividerInRect:(NSRect)aRect
{
	if (!bar || !grip) {
		// Fallback to default system drawing if images failed to load
		[super drawDividerInRect:aRect];
		return;
	}
	
	// Draw bar and grip onto the canvas
	NSRect gripRect = aRect;
	gripRect.origin.x = (NSMidX(aRect) - ([grip size].width/2));
	gripRect.size.width = [grip size].width;
	gripRect.size.height = [grip size].height;
	gripRect.origin.y = (NSMidY(aRect) - ([grip size].height/2));
	
	// Use modern drawing API
	[bar drawInRect:aRect fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0];
	[grip drawInRect:gripRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
}

- (CGFloat)dividerThickness
{
	return 10.0;
}

@end
