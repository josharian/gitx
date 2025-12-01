//
//  PBGitRevisionCellView.m
//  GitX
//
//  View-based table cell for displaying git commits
//

#import "PBGitRevisionCellView.h"
#import "PBGitHistoryController.h"
#import "GitXTextFieldCell.h"
#import "GitX-Swift.h"

static const int COLUMN_WIDTH = 10;
static const BOOL ENABLE_SHADOW = YES;
static const BOOL SHUFFLE_COLORS = NO;

@implementation PBGitRevisionGraphView

- (BOOL)isFlipped
{
	return YES;
}

+ (NSArray *)laneColors
{
	static const size_t colorCount = 8;
	static NSArray *laneColors = nil;
	if (!laneColors) {
		float segment = 1.0f / colorCount;
		NSMutableArray *colors = [NSMutableArray new];
		for (size_t i = 0; i < colorCount; ++i) {
			NSColor *newColor = [NSColor colorWithCalibratedHue:(segment * i) saturation:0.9f brightness:0.9f alpha:1.0f];
			[colors addObject:newColor];
		}
		if (SHUFFLE_COLORS) {
			NSMutableArray *shuffledColors = [NSMutableArray new];
			while (colors.count) {
				uint32_t index = arc4random_uniform(colors.count);
				[shuffledColors addObject:colors[index]];
				[colors removeObjectAtIndex:index];
			}
			colors = shuffledColors;
		}
		laneColors = [NSArray arrayWithArray:colors];
	}

	return laneColors;
}

+ (NSColor *)shadowColor
{
	static NSColor *shadowColor = nil;
	if (!shadowColor) {
		uint8_t l = 64;
		shadowColor = [NSColor colorWithCalibratedWhite:l/255.0 alpha:1.0];
	}
	return shadowColor;
}

+ (NSColor *)lineShadowColor
{
	static NSColor *shadowColor = nil;
	if (!shadowColor) {
		uint8_t l = 200;
		shadowColor = [NSColor colorWithCalibratedWhite:l/255.0 alpha:1.0];
	}
	return shadowColor;
}

- (void)drawLineFromColumn:(int)from toColumn:(int)to inRect:(NSRect)r offset:(int)offset color:(int)c
{
	NSPoint origin = r.origin;
	
	NSPoint source = NSMakePoint(origin.x + COLUMN_WIDTH * from, origin.y + offset);
	NSPoint center = NSMakePoint(origin.x + COLUMN_WIDTH * to, origin.y + r.size.height * 0.5 + 0.5);

	if (ENABLE_SHADOW) {
		[NSGraphicsContext saveGraphicsState];

		NSShadow *shadow = [NSShadow new];
		[shadow setShadowColor:[[self class] lineShadowColor]];
		[shadow setShadowOffset:NSMakeSize(0.5f, -0.5f)];
		[shadow set];
	}
	NSArray* colors = [PBGitRevisionGraphView laneColors];
	[(NSColor*)[colors objectAtIndex: ((NSUInteger)c % [colors count])] set];
	
	NSBezierPath * path = [NSBezierPath bezierPath];
	[path setLineWidth:2];
	[path setLineCapStyle:NSRoundLineCapStyle];
	[path moveToPoint: source];
	[path lineToPoint: center];
	[path stroke];

	if (ENABLE_SHADOW) {
		[NSGraphicsContext restoreGraphicsState];
	}
}

- (BOOL)isCurrentCommit
{
	NSString *thisSha = [self.commit sha];

	PBGitRepository* repository = [self.commit repository];
	NSString *currentSha = [repository headSHA];

	return [currentSha isEqual:thisSha];
}

- (void)drawCircleInRect:(NSRect)r
{
	int c = (int)self.cellInfo.position;
	NSPoint origin = r.origin;
	NSPoint columnOrigin = { origin.x + COLUMN_WIDTH * c, origin.y};

	NSRect oval = { columnOrigin.x - 5, columnOrigin.y + r.size.height * 0.5 - 5, 10, 10};

	NSBezierPath * path = [NSBezierPath bezierPathWithOvalInRect:oval];
	if (ENABLE_SHADOW && false) {
		[NSGraphicsContext saveGraphicsState];
		NSShadow *shadow = [NSShadow new];
		[shadow setShadowColor:[[self class] shadowColor]];
		[shadow setShadowOffset:NSMakeSize(0.5f, -0.5f)];
		[shadow setShadowBlurRadius:2.0f];
		[shadow set];
	}
	[[NSColor blackColor] set];
	[path fill];
	if (ENABLE_SHADOW && false) {
		[NSGraphicsContext restoreGraphicsState];
	}
	
	NSRect smallOval = { columnOrigin.x - 4, columnOrigin.y + r.size.height * 0.5 - 4, 8, 8};

	if ([self isCurrentCommit]) {
		[[NSColor colorWithCalibratedRed: 0Xfc/256.0 green:0Xa6/256.0 blue: 0X4f/256.0 alpha: 1.0] set];
	} else {
		[[NSColor whiteColor] set];
	}

	NSBezierPath *smallPath = [NSBezierPath bezierPathWithOvalInRect:smallOval];
	[smallPath fill];
}

- (void)drawTriangleInRect:(NSRect)r sign:(char)sign
{
	int c = (int)self.cellInfo.position;
	int columnHeight = 10;
	int columnWidth = 8;

	NSPoint top;
	if (sign == '<')
		top.x = round(r.origin.x) + 10 * c + 4;
	else {
		top.x = round(r.origin.x) + 10 * c - 4;
		columnWidth *= -1;
	}
	top.y = r.origin.y + (r.size.height - columnHeight) / 2;

	NSBezierPath * path = [NSBezierPath bezierPath];
	[path moveToPoint: NSMakePoint(top.x, top.y)];
	[path lineToPoint: NSMakePoint(top.x, top.y + columnHeight)];
	[path lineToPoint: NSMakePoint(top.x - columnWidth, top.y + columnHeight / 2)];
	[path closePath];

	[[NSColor whiteColor] set];
	[path fill];
	[[NSColor blackColor] set];
	[path setLineWidth: 2];
	[path stroke];
}

- (NSMutableDictionary*)attributesForRefLabelSelected:(BOOL)selected
{
	NSMutableDictionary *attributes = [[NSMutableDictionary alloc] initWithCapacity:2];
	NSMutableParagraphStyle* style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	
	[style setAlignment:NSTextAlignmentCenter];
	[attributes setObject:style forKey:NSParagraphStyleAttributeName];
	[attributes setObject:[NSFont fontWithName:@"LucidaGrande" size:10] forKey:NSFontAttributeName];

	NSShadow *shadow = nil;

	if (selected && false) {
		[attributes setObject:[NSColor alternateSelectedControlTextColor] forKey:NSForegroundColorAttributeName];
		if (ENABLE_SHADOW) {
			shadow = [NSShadow new];
			[shadow setShadowColor:[NSColor blackColor]];
			[shadow setShadowBlurRadius:2.0f];
		}
	}

	if (shadow) {
		attributes[NSShadowAttributeName] = shadow;
	}

	return attributes;
}

- (NSColor*)colorForRef:(PBGitRef*)ref
{
	BOOL isHEAD = [ref.ref isEqualToString:[[[self.controller repository] headRef] simpleRef]];

	if (isHEAD) {
		return [NSColor colorWithCalibratedRed: 0Xfc/256.0 green:0Xa6/256.0 blue: 0X4f/256.0 alpha: 1.0];
	}

	NSString* type = [ref type];
	if ([type isEqualToString:@"head"]) {
		return [NSColor colorWithCalibratedRed: 0X9a/256.0 green:0Xe2/256.0 blue: 0X84/256.0 alpha: 1.0];
	} else if ([type isEqualToString:@"remote"]) {
		return [NSColor colorWithCalibratedRed: 0xa2/256.0 green:0Xcf/256.0 blue: 0Xef/256.0 alpha: 1.0];
	} else if ([type isEqualToString:@"tag"]) {
		return [NSColor colorWithCalibratedRed: 0Xfc/256.0 green:0Xed/256.0 blue: 0X6f/256.0 alpha: 1.0];
	}
	
	return [NSColor yellowColor];
}

- (NSArray *)rectsForRefsinRect:(NSRect)rect
{
	NSMutableArray *array = [NSMutableArray array];
	
	static const int ref_padding = 10;
	static const int ref_spacing = 4;
	
	NSRect lastRect = rect;
	lastRect.origin.x = round(lastRect.origin.x);
	lastRect.origin.y = round(lastRect.origin.y);
	
	for (PBGitRef *ref in self.commit.refs) {
		NSMutableDictionary* attributes = [self attributesForRefLabelSelected:NO];
		NSSize textSize = [[ref shortName] sizeWithAttributes:attributes];
		
		NSRect newRect = lastRect;
		newRect.size.width = textSize.width + ref_padding;
		newRect.size.height = textSize.height;
		newRect.origin.y = rect.origin.y + (rect.size.height - newRect.size.height) / 2;
		
		if (NSContainsRect(rect, newRect)) {
			[array addObject:[NSValue valueWithRect:newRect]];
			lastRect = newRect;
			lastRect.origin.x += (int)lastRect.size.width + ref_spacing;
		}
	}
	
	return array;
}

- (void)drawLabelAtIndex:(int)index inRect:(NSRect)rect
{
	NSArray *refs = self.commit.refs;
	PBGitRef *ref = [refs objectAtIndex:(NSUInteger)index];
	
	NSMutableDictionary* attributes = [self attributesForRefLabelSelected:NO];
	NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:rect cornerRadius: 3.0];
	[[self colorForRef:ref] set];
	

	if (ENABLE_SHADOW) {
		[NSGraphicsContext saveGraphicsState];

		NSShadow *shadow = [NSShadow new];
		[shadow setShadowColor:[NSColor grayColor]];
		[shadow setShadowOffset:NSMakeSize(0.5f, -0.5f)];
		[shadow setShadowBlurRadius:2.0f];
		[shadow set];
	}
	[border fill];
	if (ENABLE_SHADOW) {
		[NSGraphicsContext restoreGraphicsState];
	}
	[[ref shortName] drawInRect:rect withAttributes:attributes];
}

- (void)drawRefsInRect:(NSRect *)refRect
{
	[[NSColor blackColor] setStroke];

	NSRect lastRect = NSMakeRect(0, 0, 0, 0);
	int index = 0;
	for (NSValue *rectValue in [self rectsForRefsinRect:*refRect])
	{
		NSRect rect = [rectValue rectValue];
		[self drawLabelAtIndex:index inRect:rect];
		lastRect = rect;
		++index;
	}

	if (index > 0) {
		const CGFloat PADDING = 4;
		refRect->size.width -= lastRect.origin.x - refRect->origin.x + lastRect.size.width - PADDING;
		refRect->origin.x    = lastRect.origin.x + lastRect.size.width + PADDING;
	}
}

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];
	
	if (!self.commit || !self.cellInfo) return;
	
	NSRect rect = self.bounds;
	
	if (self.cellInfo && ![self.controller hasNonlinearPath]) {
		float pathWidth = 10 + COLUMN_WIDTH * self.cellInfo.numColumns;

		NSRect ownRect;
		NSDivideRect(rect, &ownRect, &rect, pathWidth, NSMinXEdge);

		int i;
		struct PBGitGraphLine *lines = self.cellInfo.lines;
		for (i = 0; i < self.cellInfo.nLines; i++) {
			if (lines[i].upper == 0)
				[self drawLineFromColumn: lines[i].from toColumn: lines[i].to inRect:ownRect offset: ownRect.size.height color: lines[i].colorIndex];
			else
				[self drawLineFromColumn: lines[i].from toColumn: lines[i].to inRect:ownRect offset: 0 color:lines[i].colorIndex];
		}

		if (self.cellInfo.sign == '<' || self.cellInfo.sign == '>')
			[self drawTriangleInRect: ownRect sign: self.cellInfo.sign];
		else
			[self drawCircleInRect: ownRect];
	}

	if ([self.commit refs] && [[self.commit refs] count])
		[self drawRefsInRect:&rect];
	
	// Draw the subject text
	NSMutableDictionary *attributes = [[NSMutableDictionary alloc] init];
	[attributes setObject:[NSFont systemFontOfSize:12] forKey:NSFontAttributeName];
	
	// Check if this cell view's background style indicates selection
	PBGitRevisionCellView *cellView = (PBGitRevisionCellView *)[self superview];
	BOOL isSelected = NO;
	if ([cellView isKindOfClass:[PBGitRevisionCellView class]]) {
		isSelected = (cellView.backgroundStyle == NSBackgroundStyleEmphasized || cellView.backgroundStyle == NSBackgroundStyleDark);
	}
	
	if (isSelected) {
		[attributes setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];
	} else {
		[attributes setObject:[NSColor controlTextColor] forKey:NSForegroundColorAttributeName];
	}
	
	NSString *subject = [self.commit subject];
	if (subject) {
		// Adjust rect for text drawing
		rect.origin.x += 4;
		rect.size.width -= 8;
		[subject drawInRect:rect withAttributes:attributes];
	}
}

- (int)indexAtX:(float)x
{
	float pathWidth = 0;
	if (self.cellInfo && ![self.controller hasNonlinearPath])
		pathWidth = 10 + 10 * self.cellInfo.numColumns;

	int index = 0;
	NSRect refRect = NSMakeRect(pathWidth, 0, 1000, 10000);
	for (NSValue *rectValue in [self rectsForRefsinRect:refRect])
	{
		NSRect rect = [rectValue rectValue];
		if (x >= rect.origin.x && x <= (rect.origin.x + rect.size.width))
			return index;
		++index;
	}

	return -1;
}

- (NSRect)rectAtIndex:(int)index
{
	float pathWidth = 0;
	if (self.cellInfo && ![self.controller hasNonlinearPath])
		pathWidth = 10 + 10 * self.cellInfo.numColumns;
	NSRect refRect = NSMakeRect(pathWidth, 0, 1000, 10000);

	return [[[self rectsForRefsinRect:refRect] objectAtIndex:(NSUInteger)index] rectValue];
}

- (void)rightMouseDown:(NSEvent *)event
{
	if (!self.contextMenuDelegate) {
		[super rightMouseDown:event];
		return;
	}

	NSPoint locationInView = [self convertPoint:[event locationInWindow] fromView:nil];
	int i = [self indexAtX:locationInView.x];

	id ref = nil;
	if (i >= 0)
		ref = [[self.commit refs] objectAtIndex:(NSUInteger)i];

	NSArray *items = nil;
	if (ref)
		items = [self.contextMenuDelegate menuItemsForRef:ref];
	else
		items = [self.contextMenuDelegate menuItemsForCommit:self.commit];

	NSMenu *menu = [[NSMenu alloc] init];
	[menu setAutoenablesItems:NO];
	for (NSMenuItem *item in items)
		[menu addItem:item];
	
	[NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

@end

@implementation PBGitRevisionCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self) {
		[self setupViews];
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if (self) {
		[self setupViews];
	}
	return self;
}

- (void)setupViews
{
	self.graphView = [[PBGitRevisionGraphView alloc] initWithFrame:NSZeroRect];
	self.graphView.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:self.graphView];
	
	[NSLayoutConstraint activateConstraints:@[
		[self.graphView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
		[self.graphView.topAnchor constraintEqualToAnchor:self.topAnchor],
		[self.graphView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
		[self.graphView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor]
	]];
}

- (void)configureForCommit:(PBGitCommit *)commit withCellInfo:(PBGraphCellInfo *)cellInfo
{
	self.commit = commit;
	self.graphView.commit = commit;
	self.graphView.cellInfo = cellInfo;
	
	[self.graphView setNeedsDisplay:YES];
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
	[super setBackgroundStyle:backgroundStyle];
	[self.graphView setNeedsDisplay:YES];
}

@end
