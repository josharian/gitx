//
//  PBGitTableCellView.m
//  GitX
//
//  NSTableCellView subclass that properly handles text color for selection
//

#import "PBGitTableCellView.h"

@implementation PBGitTableCellView

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
	[super setBackgroundStyle:backgroundStyle];
	
	// Update text color based on background style
	if (backgroundStyle == NSBackgroundStyleEmphasized || backgroundStyle == NSBackgroundStyleDark) {
		// Selected - use white text
		self.textField.textColor = [NSColor whiteColor];
	} else {
		// Not selected - use normal text color
		self.textField.textColor = [NSColor controlTextColor];
		
		// For monospaced fields, check if it's a SHA column
		NSTableColumn *column = nil;
		NSTableView *tableView = (NSTableView *)self.superview.superview;
		if ([tableView isKindOfClass:[NSTableView class]]) {
			NSInteger colIndex = [tableView columnForView:self];
			if (colIndex >= 0 && colIndex < tableView.tableColumns.count) {
				column = [tableView.tableColumns objectAtIndex:colIndex];
			}
		}
		
		// Keep monospaced font for SHA columns
		if (column && ([[column identifier] isEqualToString:@"SHAColumn"] || 
		              [[column identifier] isEqualToString:@"ShortSHAColumn"])) {
			// SHA columns stay with their monospaced font
		}
	}
}

@end