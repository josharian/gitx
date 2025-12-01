//
//  PBRepositoryDocumentController.mm
//  GitX
//
//  Created by Ciarán Walsh on 15/08/2008.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBRepositoryDocumentController.h"
#import "PBGitRepository.h"
#import "PBGitRevList.h"
#import "PBGitBinary.h"
#import "GitX-Swift.h"

@implementation PBRepositoryDocumentController
// This method is overridden to configure the open panel to only allow
// selection of directories
- (NSInteger)runModalOpenPanel:(NSOpenPanel *)openPanel forTypes:(NSArray *)extensions
{
	[openPanel setCanChooseFiles:YES];
	[openPanel setCanChooseDirectories:YES];
	[openPanel setAllowedFileTypes:[NSArray arrayWithObject:@"git"]];
	return [openPanel runModal];
}

- (id)makeUntitledDocumentOfType:(NSString *)typeName error:(NSError *__autoreleasing *)outError {
	NSOpenPanel *op = [NSOpenPanel openPanel];

	[op setCanChooseFiles:NO];
	[op setCanChooseDirectories:YES];
	[op setAllowsMultipleSelection:NO];
	[op setMessage:@"Initialize a repository here:"];
	[op setTitle:@"New Repository"];
	if ([op runModal] != NSModalResponseOK) {
		if (outError) {
			*outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
		}
        return nil;
    }

    NSString *gitPath = [PBGitBinary path];
    if (!gitPath) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"GitXError" 
                                           code:1 
                                       userInfo:@{NSLocalizedDescriptionKey: @"Git binary not found"}];
        }
        return nil;
    }
    
    int exitCode = 0;
    (void)[PBEasyPipe outputForCommand:gitPath
                        withArgs:@[@"init"]
                           inDir:[[op URL] path]
                        retValue:&exitCode];
    
    BOOL success = (exitCode == 0);
    
    if (!success) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"GitXError" 
                                           code:1 
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to initialize Git repository"}];
        }
        return nil; // Repo creation failed
    }

    return [[PBGitRepository alloc] initWithContentsOfURL:[op URL] ofType:PBGitRepositoryDocumentType error:outError];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
	if ([item action] == @selector(newDocument:))
		return ([PBGitBinary path] != nil);
	return [super validateMenuItem:item];
}

@end
