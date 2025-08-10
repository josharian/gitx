//
//  PBUnsortableTableHeader.m
//  GitX
//
//  Created by Pieter de Bie on 03-10-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBUnsortableTableHeader.h"


@implementation PBUnsortableTableHeader

- (void)mouseDown:(NSEvent *)theEvent
{
	// Don't pass the mouse down to super, which would trigger sorting
	// This completely disables column header clicking for sorting
}
@end
