//
//  PBGitRepository.m
//  GitTest
//
//  Created by Pieter de Bie on 13-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitRepository.h"
#import "PBGitCommit.h"
#import "PBGitWindowController.h"
#import "PBGitBinary.h"
#import "GTObjectiveGitStubs.h"

#import "NSFileHandleExt.h"
#import "PBEasyPipe.h"
#import "PBGitRef.h"
#import "PBGitRevSpecifier.h"
#import "PBGitRevList.h"
#import "PBGitDefaults.h"
#import "GitXScriptingConstants.h"
#import "PBHistorySearchController.h"
#import "PBGitRepositoryWatcher.h"
#import "GitRepoFinder.h"
#import "PBGitHistoryList.h"
#import "PBGitSVSubmoduleItem.h"


NSString *PBGitRepositoryDocumentType = @"Git Repository";

@interface PBGitRepository ()

@property (nonatomic, strong) NSNumber *hasSVNRepoConfig;

@end

@implementation PBGitRepository

@synthesize revisionList, branchesSet, currentBranch, refs, hasChanged;
@synthesize currentBranchFilter;

#pragma mark -
#pragma mark Memory management

- (id)init
{
    self = [super init];
    if (!self) return nil;

	self.branchesSet = [NSMutableOrderedSet orderedSet];
    self.submodules = [NSMutableArray array];
	currentBranchFilter = [PBGitDefaults branchFilter];
    return self;
}

- (void) dealloc
{
	// NSLog(@"Dealloc of repository");
	[watcher stop];
}


#pragma mark -
#pragma mark NSDocument API

// NSFileWrapper is broken and doesn't work when called on a directory containing a large number of directories and files.
//because of this it is safer to implement readFromURL than readFromFileWrapper.
//Because NSFileManager does not attempt to recursively open all directories and file when fileExistsAtPath is called
//this works much better.
- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
	if (![PBGitBinary path])
	{
		if (outError) {
			NSDictionary* userInfo = [NSDictionary dictionaryWithObject:[PBGitBinary notFoundError]
																 forKey:NSLocalizedRecoverySuggestionErrorKey];
			*outError = [NSError errorWithDomain:PBGitRepositoryErrorDomain code:0 userInfo:userInfo];
		}
		return NO;
	}

	BOOL isDirectory = FALSE;
	[[NSFileManager defaultManager] fileExistsAtPath:[absoluteURL path] isDirectory:&isDirectory];
	if (!isDirectory) {
		if (outError) {
			NSDictionary* userInfo = [NSDictionary dictionaryWithObject:@"Reading files is not supported."
																 forKey:NSLocalizedRecoverySuggestionErrorKey];
			*outError = [NSError errorWithDomain:PBGitRepositoryErrorDomain code:0 userInfo:userInfo];
		}
		return NO;
	}

    NSError *error = nil;
	NSURL *repoURL = [GitRepoFinder gitDirForURL:absoluteURL];
    
    // Use git rev-parse to validate this is a git repository
    NSTask *validateTask = [[NSTask alloc] init];
    validateTask.launchPath = @"/usr/bin/git";
    validateTask.arguments = @[@"rev-parse", @"--git-dir"];
    validateTask.currentDirectoryPath = [absoluteURL path];
    
    NSPipe *validatePipe = [NSPipe pipe];
    validateTask.standardOutput = validatePipe;
    validateTask.standardError = [NSPipe pipe];
    
    BOOL isValidRepo = NO;
    @try {
        [validateTask launch];
        [validateTask waitUntilExit];
        
        if (validateTask.terminationStatus == 0) {
            isValidRepo = YES;
        }
    }
    @catch (NSException *exception) {
        isValidRepo = NO;
    }
    
    _gtRepo = [[GTRepository alloc] init];
	if (!isValidRepo) {
		if (outError) {
			NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSString stringWithFormat:@"%@ does not appear to be a git repository.", [[self fileURL] path]], NSLocalizedRecoverySuggestionErrorKey,
                                      error, NSUnderlyingErrorKey,
                                      nil];
			*outError = [NSError errorWithDomain:PBGitRepositoryErrorDomain code:0 userInfo:userInfo];
		}
		return NO;
	}

	revisionList = [[PBGitHistoryList alloc] initWithRepository:self];

	[self reloadRefs];

    // Setup the FSEvents watcher to fire notifications when things change
    watcher = [[PBGitRepositoryWatcher alloc] initWithRepository:self];

	return YES;
}

- (void)close
{
	[revisionList cleanup];

	[super close];
}

- (BOOL)isDocumentEdited
{
	return NO;
}

- (NSString *)displayName
{
    // Build our display name depending on the current HEAD and whether it's detached or not
    // Check if HEAD is detached using git symbolic-ref
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/git";
    task.arguments = @[@"symbolic-ref", @"HEAD"];
    task.currentDirectoryPath = [self workingDirectory];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        // If symbolic-ref fails, HEAD is detached
        if (task.terminationStatus != 0)
            return [NSString localizedStringWithFormat:@"%@ (detached HEAD)", self.projectName];
    }
    @catch (NSException *exception) {
        // If git is not available, assume not detached
    }

    return [NSString localizedStringWithFormat:@"%@ (branch: %@)", self.projectName, [[self headRef] description]];
}

- (void)makeWindowControllers
{
    // Create our custom window controller
#ifndef CLI
	[self addWindowController: [[PBGitWindowController alloc] initWithRepository:self displayDefault:YES]];
#endif
}

// see if the current appleEvent has the command line arguments from the gitx cli
// this could be from an openApplication or an openDocument apple event
// when opening a repository this is called before the sidebar controller gets it's awakeFromNib: message
// if the repository is already open then this is also a good place to catch the event as the window is about to be brought forward
- (void)showWindows
{
	NSAppleEventDescriptor *currentAppleEvent = [[NSAppleEventManager sharedAppleEventManager] currentAppleEvent];

	if (currentAppleEvent) {
		NSAppleEventDescriptor *eventRecord = [currentAppleEvent paramDescriptorForKeyword:keyAEPropData];

		// on app launch there may be many repositories opening, so double check that this is the right repo
		NSString *path = [[eventRecord paramDescriptorForKeyword:typeFileURL] stringValue];
		if (path) {
			NSURL *workingDirectory = [NSURL URLWithString:path];
			if ([[GitRepoFinder gitDirForURL:workingDirectory] isEqual:[self fileURL]]) {
				NSAppleEventDescriptor *argumentsList = [eventRecord paramDescriptorForKeyword:kGitXAEKeyArgumentsList];
				[self handleGitXScriptingArguments:argumentsList inWorkingDirectory:workingDirectory];

				// showWindows may be called more than once during app launch so remove the CLI data after we handle the event
				[currentAppleEvent removeDescriptorWithKeyword:keyAEPropData];
			}
		}
	}

	[super showWindows];
}

#pragma mark -
#pragma mark Properties/General methods

- (NSURL *)getIndexURL
{
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/usr/bin/git";
	task.arguments = @[@"rev-parse", @"--git-path", @"index"];
	task.currentDirectoryPath = [self workingDirectory];
	
	NSPipe *pipe = [NSPipe pipe];
	task.standardOutput = pipe;
	
	[task launch];
	[task waitUntilExit];
	
	if (task.terminationStatus != 0) {
		// Fallback to standard path if git command fails
		NSString *indexPath = [[self workingDirectory] stringByAppendingPathComponent:@".git/index"];
		return [NSURL fileURLWithPath:indexPath];
	}
	
	NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
	NSString *indexPath = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	indexPath = [indexPath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	// Convert relative path to absolute path
	if (![indexPath isAbsolutePath]) {
		indexPath = [[self workingDirectory] stringByAppendingPathComponent:indexPath];
	}
	
	return [NSURL fileURLWithPath:indexPath];
}

- (BOOL)isBareRepository
{
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/git";
    task.arguments = @[@"config", @"--get", @"core.bare"];
    task.currentDirectoryPath = [self workingDirectory];
    
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        if (task.terminationStatus == 0) {
            NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
            NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            return [result isEqualToString:@"true"];
        }
    }
    @catch (NSException *exception) {
        // Git not available or other error
    }
    
    return NO;
}

- (BOOL)readHasSVNRemoteFromConfig
{
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/git";
    task.arguments = @[@"config", @"--get-regexp", @"^svn-remote\\."];
    task.currentDirectoryPath = [self workingDirectory];
    
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        // If we find any svn-remote config, return YES
        return task.terminationStatus == 0;
    }
    @catch (NSException *exception) {
        // Git not available or other error
    }
    
    return NO;
}

- (BOOL)hasSVNRemote
{
	if (!self.hasSVNRepoConfig) {
		self.hasSVNRepoConfig = @([self readHasSVNRemoteFromConfig]);
	}
	return [self.hasSVNRepoConfig boolValue];
}

- (NSURL *)gitURL {
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/usr/bin/git";
	task.arguments = @[@"rev-parse", @"--git-dir"];
	task.currentDirectoryPath = [self workingDirectory];
	
	NSPipe *pipe = [NSPipe pipe];
	task.standardOutput = pipe;
	
	@try {
		[task launch];
		[task waitUntilExit];
		
		if (task.terminationStatus == 0) {
			NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
			NSString *gitPath = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			gitPath = [gitPath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			
			// Convert relative path to absolute path
			if (![gitPath isAbsolutePath]) {
				gitPath = [[self workingDirectory] stringByAppendingPathComponent:gitPath];
			}
			
			return [NSURL fileURLWithPath:gitPath];
		}
	}
	@catch (NSException *exception) {
		NSLog(@"Error getting git directory: %@", exception.reason);
	}
	
	// Fallback to standard path if git command fails
	NSString *gitPath = [[self workingDirectory] stringByAppendingPathComponent:@".git"];
	return [NSURL fileURLWithPath:gitPath];
}

- (void)forceUpdateRevisions
{
	[revisionList forceUpdate];
}

- (NSString *)projectName
{
	NSString* result = [self.workingDirectory lastPathComponent];
	return result;
}

// Get the .gitignore file at the root of the repository
- (NSString *)gitIgnoreFilename
{
	return [[self workingDirectory] stringByAppendingPathComponent:@".gitignore"];
}

- (PBGitWindowController *)windowController
{
	if ([[self windowControllers] count] == 0)
		return NULL;
	
	return [[self windowControllers] objectAtIndex:0];
}

- (void)addRef:(PBGitRef *)ref
{
    if (!ref || !self.refs) {
        return;
    }
    
    NSString *refName = [ref ref];
    if (refName) {
        [self.refs setObject:ref forKey:refName];
    }
}

- (void)loadSubmodules
{
    self.submodules = [NSMutableArray array];
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/git";
    task.arguments = @[@"submodule", @"status"];
    task.currentDirectoryPath = [self workingDirectory];
    
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        if (task.terminationStatus == 0) {
            NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
            NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            
            if ([output length] > 0) {
                NSArray *lines = [output componentsSeparatedByString:@"\n"];
                for (NSString *line in lines) {
                    // Git submodule status format: " <sha> <path> (<description>)"
                    // First character indicates status: ' ' initialized, '-' not initialized, '+' modified
                    if ([line length] > 42) { // Minimum: status char + 40 char SHA + space + path
                        NSString *trimmedLine = [line substringFromIndex:1]; // Skip status character
                        NSArray *components = [trimmedLine componentsSeparatedByString:@" "];
                        if ([components count] >= 2) {
                            NSString *path = [components objectAtIndex:1];
                            
                            PBSubmoduleInfo *submoduleInfo = [[PBSubmoduleInfo alloc] init];
                            submoduleInfo.name = [path lastPathComponent];
                            submoduleInfo.path = path;
                            submoduleInfo.parentRepositoryURL = [NSURL fileURLWithPath:[self workingDirectory]];
                            
                            [self.submodules addObject:submoduleInfo];
                        }
                    }
                }
            }
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Error loading submodules: %@", exception.reason);
    }
}

- (void) reloadRefs
{
	// clear out ref caches
	_headRef = nil;
	_headSha = nil;
	self->refs = [NSMutableDictionary dictionary];
	
	// Use git for-each-ref to enumerate all references
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/usr/bin/git";
	task.arguments = @[@"for-each-ref", @"--format=%(refname)%09%(objecttype)"];
	task.currentDirectoryPath = [self workingDirectory];
	
	NSPipe *pipe = [NSPipe pipe];
	task.standardOutput = pipe;
	task.standardError = [NSPipe pipe];
	
	NSMutableOrderedSet *oldBranches = [self.branchesSet mutableCopy];
	
	@try {
		[task launch];
		[task waitUntilExit];
		
		if (task.terminationStatus == 0) {
			NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
			NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			
			if ([output length] > 0) {
				NSArray *lines = [output componentsSeparatedByString:@"\n"];
				for (NSString *line in lines) {
					// Format: refname<tab>objecttype
					NSArray *components = [line componentsSeparatedByString:@"\t"];
					if ([components count] >= 2) {
						NSString *referenceName = [components objectAtIndex:0];
						NSString *objectType = [components objectAtIndex:1];
						
						// Skip symbolic references like origin/HEAD that point to other refs
						if ([objectType isEqualToString:@"commit"] || [objectType isEqualToString:@"tag"]) {
							PBGitRef* gitRef = [PBGitRef refFromString:referenceName];
							PBGitRevSpecifier* revSpec = [[PBGitRevSpecifier alloc] initWithRef:gitRef];
							[self addBranch:revSpec];
							[oldBranches removeObject:revSpec];
						}
					}
				}
			}
		}
	}
	@catch (NSException *exception) {
		NSLog(@"Error loading refs: %@", exception.reason);
	}
	
	// Remove old branches that no longer exist
	for (PBGitRevSpecifier *branch in oldBranches)
		if ([branch isSimpleRef] && ![branch isEqual:[self headRef]])
			[self removeBranch:branch];

    [self loadSubmodules];
    
	[self willChangeValueForKey:@"refs"];
	[self didChangeValueForKey:@"refs"];

	[[[self windowController] window] setTitle:[self displayName]];
}

- (void) lazyReload
{
	if (!hasChanged)
		return;

	[self.revisionList updateHistory];
	hasChanged = NO;
}

- (PBGitRevSpecifier *)headRef
{
	if (_headRef)
		return _headRef;

	NSString* branch = [self parseSymbolicReference: @"HEAD"];
	if (branch && [branch hasPrefix:@"refs/heads/"])
		_headRef = [[PBGitRevSpecifier alloc] initWithRef:[PBGitRef refFromString:branch]];
	else
		_headRef = [[PBGitRevSpecifier alloc] initWithRef:[PBGitRef refFromString:@"HEAD"]];

	_headSha = [self shaForRef:[_headRef ref]];

	return _headRef;
}

- (GTOID *)headSHA
{
	if (! _headSha)
		[self headRef];

	return _headSha;
}

- (PBGitCommit *)headCommit
{
	return [self commitForSHA:[self headSHA]];
}

- (GTOID *)shaForRef:(PBGitRef *)ref
{
	if (!ref)
		return nil;
	
	for (GTOID *sha in refs)
	{
		NSMutableSet *refsForSha = [refs objectForKey:sha];
		for (PBGitRef *existingRef in refsForSha)
		{
			if ([existingRef isEqualToRef:ref])
			{
				return sha;
			}
		}
    }
    
	
	// Use git rev-parse to resolve the ref to a SHA
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/usr/bin/git";
	task.arguments = @[@"rev-parse", ref.ref];
	task.currentDirectoryPath = [self workingDirectory];
	
	NSPipe *pipe = [NSPipe pipe];
	task.standardOutput = pipe;
	task.standardError = [NSPipe pipe];
	
	@try {
		[task launch];
		[task waitUntilExit];
		
		if (task.terminationStatus == 0) {
			NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
			NSString *shaString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			shaString = [shaString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			
			if (shaString.length > 0) {
				return [GTOID oidWithSHA:shaString];
			}
		}
	}
	@catch (NSException *exception) {
		NSLog(@"Error looking up ref for %@: %@", ref.ref, exception.reason);
	}
	
	return nil;
}

- (PBGitCommit *)commitForRef:(PBGitRef *)ref
{
	if (!ref)
		return nil;

	return [self commitForSHA:[self shaForRef:ref]];
}

- (PBGitCommit *)commitForSHA:(GTOID *)sha
{
	if (!sha)
		return nil;
	NSArray *revList = revisionList.projectCommits;

    if (!revList) {
        [revisionList forceUpdate];
        revList = revisionList.projectCommits;
    }
	for (PBGitCommit *commit in revList)
		if ([[commit sha] isEqual:sha])
			return commit;

	return nil;
}

- (BOOL)isOnSameBranch:(GTOID *)branchSHA asSHA:(GTOID *)testSHA
{
	if (!branchSHA || !testSHA)
		return NO;

	if ([testSHA isEqual:branchSHA])
		return YES;

	NSArray *revList = revisionList.projectCommits;

	NSMutableSet *searchSHAs = [NSMutableSet setWithObject:branchSHA];

	for (PBGitCommit *commit in revList) {
		GTOID *commitSHA = [commit sha];
		if ([searchSHAs containsObject:commitSHA]) {
			if ([testSHA isEqual:commitSHA])
				return YES;
			[searchSHAs removeObject:commitSHA];
			[searchSHAs addObjectsFromArray:commit.parents];
		}
		else if ([testSHA isEqual:commitSHA])
			return NO;
	}

	return NO;
}

- (BOOL)isSHAOnHeadBranch:(GTOID *)testSHA
{
	if (!testSHA)
		return NO;

	GTOID *headSHA = [self headSHA];

	if ([testSHA isEqual:headSHA])
		return YES;

	return [self isOnSameBranch:headSHA asSHA:testSHA];
}

- (BOOL)isRefOnHeadBranch:(PBGitRef *)testRef
{
	if (!testRef)
		return NO;

	return [self isSHAOnHeadBranch:[self shaForRef:testRef]];
}

- (BOOL) checkRefFormat:(NSString *)refName
{
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/usr/bin/git";
	task.arguments = @[@"check-ref-format", refName];
	task.currentDirectoryPath = [self workingDirectory];
	task.standardOutput = [NSPipe pipe];
	task.standardError = [NSPipe pipe];
	
	@try {
		[task launch];
		[task waitUntilExit];
		
		// git check-ref-format returns 0 for valid refs
		return task.terminationStatus == 0;
	}
	@catch (NSException *exception) {
		// If git is not available, assume valid
		return YES;
	}
}

- (BOOL) refExists:(PBGitRef *)ref
{
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/usr/bin/git";
	task.arguments = @[@"show-ref", @"--verify", @"--quiet", ref.ref];
	task.currentDirectoryPath = [self workingDirectory];
	task.standardOutput = [NSPipe pipe];
	task.standardError = [NSPipe pipe];
	
	@try {
		[task launch];
		[task waitUntilExit];
		
		// git show-ref --verify returns 0 if ref exists
		return task.terminationStatus == 0;
	}
	@catch (NSException *exception) {
		// If git is not available, assume ref doesn't exist
		return NO;
	}
}

// useful for getting the full ref for a user entered name
// EX:  name: master
//       ref: refs/heads/master
- (PBGitRef *)refForName:(NSString *)name
{
	if (!name)
		return nil;

	int retValue = 1;
    NSString *output = [self outputInWorkdirForArguments:[NSArray arrayWithObjects:@"show-ref", name, nil] retValue:&retValue];
	if (retValue)
		return nil;

	// the output is in the format: <SHA-1 ID> <space> <reference name>
	// with potentially multiple lines if there are multiple matching refs (ex: refs/remotes/origin/master)
	// here we only care about the first match
	NSArray *refList = [output componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([refList count] > 1) {
		NSString *refName = [refList objectAtIndex:1];
		return [PBGitRef refFromString:refName];
	}

	return nil;
}

- (NSArray*)branches
{
    return [self.branchesSet array];
}
		
// Returns either this object, or an existing, equal object
- (PBGitRevSpecifier*) addBranch:(PBGitRevSpecifier*)branch
{
	if ([[branch parameters] count] == 0)
		branch = [self headRef];

	// First check if the branch doesn't exist already
    if ([self.branchesSet containsObject:branch]) {
        return branch;
    }

	NSIndexSet *newIndex = [NSIndexSet indexSetWithIndex:[self.branches count]];
	[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:newIndex forKey:@"branches"];

    [self.branchesSet addObject:branch];

	[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:newIndex forKey:@"branches"];
	return branch;
}

- (BOOL) removeBranch:(PBGitRevSpecifier *)branch
{
    if ([self.branchesSet containsObject:branch]) {
        NSIndexSet *oldIndex = [NSIndexSet indexSetWithIndex:[self.branches indexOfObject:branch]];
        [self willChange:NSKeyValueChangeRemoval valuesAtIndexes:oldIndex forKey:@"branches"];

        [self.branchesSet removeObject:branch];

        [self didChange:NSKeyValueChangeRemoval valuesAtIndexes:oldIndex forKey:@"branches"];
        return YES;
    }
	return NO;
}
	
- (void) readCurrentBranch
{
		self.currentBranch = [self addBranch: [self headRef]];
}

- (NSString *) workingDirectory
{
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/usr/bin/git";
	task.arguments = @[@"rev-parse", @"--show-toplevel"];
	task.currentDirectoryPath = self.fileURL.path;
	
	NSPipe *pipe = [NSPipe pipe];
	task.standardOutput = pipe;
	task.standardError = [NSPipe pipe];
	
	@try {
		[task launch];
		[task waitUntilExit];
		
		if (task.terminationStatus == 0) {
			NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
			NSString *workdir = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			workdir = [workdir stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			
			if (workdir.length > 0) {
				return [workdir stringByStandardizingPath];
			}
		}
	}
	@catch (NSException *exception) {
		// Git not available or other error, fall back
	}
	
	// Fallback to original logic
	return self.fileURL.path;
}

#pragma mark Remotes

- (NSArray *) remotes
{
	int retValue = 1;
	NSString *remotes = [self outputInWorkdirForArguments:[NSArray arrayWithObject:@"remote"] retValue:&retValue];
	if (retValue || [remotes isEqualToString:@""])
		return nil;

	return [remotes componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

- (BOOL) hasRemotes
{
	return ([self remotes] != nil);
}

- (PBGitRef *) remoteRefForBranch:(PBGitRef *)branch error:(NSError **)error
{
	if ([branch isRemote]) {
		return [branch remoteRef];
	}

	// Use git config to find the remote tracking branch
	NSString *branchName = [branch shortName];
	if (branchName) {
		NSTask *gitTask = [[NSTask alloc] init];
		gitTask.launchPath = @"/usr/bin/git";
		gitTask.arguments = @[@"config", [NSString stringWithFormat:@"branch.%@.merge", branchName]];
		gitTask.currentDirectoryPath = [self.fileURL path];
		
		NSPipe *outputPipe = [NSPipe pipe];
		gitTask.standardOutput = outputPipe;
		gitTask.standardError = [NSPipe pipe];
		
		@try {
			[gitTask launch];
			[gitTask waitUntilExit];
			
			if (gitTask.terminationStatus == 0) {
				NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
				NSString *mergeRef = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
				mergeRef = [mergeRef stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
				
				if (mergeRef.length > 0) {
					// Get the remote name
					NSTask *remoteTask = [[NSTask alloc] init];
					remoteTask.launchPath = @"/usr/bin/git";
					remoteTask.arguments = @[@"config", [NSString stringWithFormat:@"branch.%@.remote", branchName]];
					remoteTask.currentDirectoryPath = [self.fileURL path];
					
					NSPipe *remoteOutputPipe = [NSPipe pipe];
					remoteTask.standardOutput = remoteOutputPipe;
					remoteTask.standardError = [NSPipe pipe];
					
					[remoteTask launch];
					[remoteTask waitUntilExit];
					
					if (remoteTask.terminationStatus == 0) {
						NSData *remoteOutputData = [[remoteOutputPipe fileHandleForReading] readDataToEndOfFile];
						NSString *remoteName = [[NSString alloc] initWithData:remoteOutputData encoding:NSUTF8StringEncoding];
						remoteName = [remoteName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
						
						if (remoteName.length > 0) {
							// Convert refs/heads/branch to refs/remotes/remote/branch
							if ([mergeRef hasPrefix:@"refs/heads/"]) {
								NSString *branchPart = [mergeRef substringFromIndex:[@"refs/heads/" length]];
								NSString *trackingRefName = [NSString stringWithFormat:@"refs/remotes/%@/%@", remoteName, branchPart];
								PBGitRef *trackingBranchRef = [PBGitRef refFromString:trackingRefName];
								return trackingBranchRef;
							}
						}
					}
				}
			}
		}
		@catch (NSException *exception) {
			// Fall through to error handling below
		}
	}

	if (error != NULL) {
		NSString *info = [NSString stringWithFormat:@"There is no remote configured for the %@ '%@'.\n\nPlease select a branch from the popup menu, which has a corresponding remote tracking branch set up.\n\nYou can also use a contextual menu to choose a branch by right clicking on its label in the commit history list.", [branch refishType], [branch shortName]];
		*error = [NSError errorWithDomain:PBGitRepositoryErrorDomain code:0
								 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
										   @"No remote configured for branch", NSLocalizedDescriptionKey,
										   info, NSLocalizedRecoverySuggestionErrorKey,
										   nil]];
	}
	return nil;
}

- (NSString *) infoForRemote:(NSString *)remoteName
{
	int retValue = 1;
	NSString *output = [self outputInWorkdirForArguments:[NSArray arrayWithObjects:@"remote", @"show", remoteName, nil] retValue:&retValue];
	if (retValue)
		return nil;

	return output;
}

#pragma mark Repository commands

- (void) cloneRepositoryToPath:(NSString *)path bare:(BOOL)isBare
{
	if (!path || [path isEqualToString:@""])
		return;

	NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"clone", @"--no-hardlinks", @"--", @".", path, nil];
	if (isBare)
		[arguments insertObject:@"--bare" atIndex:1];

	// Cloning has been disabled in this version
}


- (BOOL) checkoutRefish:(id <PBGitRefish>)ref
{
	NSString *refName = nil;
	if ([ref refishType] == kGitXBranchType)
		refName = [ref shortName];
	else
		refName = [ref refishName];

	int retValue = 1;
	NSArray *arguments = [NSArray arrayWithObjects:@"checkout", refName, nil];
	NSString *output = [self outputInWorkdirForArguments:arguments retValue:&retValue];
	if (retValue) {
		NSString *message = [NSString stringWithFormat:@"There was an error checking out the %@ '%@'.\n\nPerhaps your working directory is not clean?", [ref refishType], [ref shortName]];
		[self.windowController showErrorSheetTitle:@"Checkout failed!" message:message arguments:arguments output:output];
		return NO;
	}

	[self reloadRefs];
	[self readCurrentBranch];
	return YES;
}

- (BOOL) checkoutFiles:(NSArray *)files fromRefish:(id <PBGitRefish>)ref
{
	if (!files || ([files count] == 0))
		return NO;

	NSString *refName = nil;
	if ([ref refishType] == kGitXBranchType)
		refName = [ref shortName];
	else
		refName = [ref refishName];

	int retValue = 1;
	NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"checkout", refName, @"--", nil];
	[arguments addObjectsFromArray:files];
	NSString *output = [self outputInWorkdirForArguments:arguments retValue:&retValue];
	if (retValue) {
		NSString *message = [NSString stringWithFormat:@"There was an error checking out the file(s) from the %@ '%@'.\n\nPerhaps your working directory is not clean?", [ref refishType], [ref shortName]];
		[self.windowController showErrorSheetTitle:@"Checkout failed!" message:message arguments:arguments output:output];
		return NO;
	}

	return YES;
}


- (BOOL) mergeWithRefish:(id <PBGitRefish>)ref
{
	NSString *refName = [ref refishName];

	int retValue = 1;
	NSArray *arguments = [NSArray arrayWithObjects:@"merge", refName, nil];
	NSString *output = [self outputInWorkdirForArguments:arguments retValue:&retValue];
	if (retValue) {
		NSString *headName = [[[self headRef] ref] shortName];
		NSString *message = [NSString stringWithFormat:@"There was an error merging %@ into %@.", refName, headName];
		[self.windowController showErrorSheetTitle:@"Merge failed!" message:message arguments:arguments output:output];
		return NO;
	}

	[self reloadRefs];
	[self readCurrentBranch];
	return YES;
}

- (BOOL) cherryPickRefish:(id <PBGitRefish>)ref
{
	if (!ref)
		return NO;

	NSString *refName = [ref refishName];

	int retValue = 1;
	NSArray *arguments = [NSArray arrayWithObjects:@"cherry-pick", refName, nil];
	NSString *output = [self outputInWorkdirForArguments:arguments retValue:&retValue];
	if (retValue) {
		NSString *message = [NSString stringWithFormat:@"There was an error cherry picking the %@ '%@'.\n\nPerhaps your working directory is not clean?", [ref refishType], [ref shortName]];
		[self.windowController showErrorSheetTitle:@"Cherry pick failed!" message:message arguments:arguments output:output];
		return NO;
	}

	[self reloadRefs];
	[self readCurrentBranch];
	return YES;
}

- (BOOL) rebaseBranch:(id <PBGitRefish>)branch onRefish:(id <PBGitRefish>)upstream
{
	if (!upstream)
		return NO;

	NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"rebase", [upstream refishName], nil];

	if (branch)
		[arguments addObject:[branch refishName]];

	int retValue = 1;
	NSString *output = [self outputInWorkdirForArguments:arguments retValue:&retValue];
	if (retValue) {
		NSString *branchName = @"HEAD";
		if (branch)
			branchName = [NSString stringWithFormat:@"%@ '%@'", [branch refishType], [branch shortName]];
		NSString *message = [NSString stringWithFormat:@"There was an error rebasing %@ with %@ '%@'.", branchName, [upstream refishType], [upstream shortName]];
		[self.windowController showErrorSheetTitle:@"Rebase failed!" message:message arguments:arguments output:output];
		return NO;
	}

	[self reloadRefs];
	[self readCurrentBranch];
	return YES;
}

- (BOOL) createBranch:(NSString *)branchName atRefish:(id <PBGitRefish>)ref
{
	if (!branchName || !ref)
		return NO;

	int retValue = 1;
	NSArray *arguments = [NSArray arrayWithObjects:@"branch", branchName, [ref refishName], nil];
	NSString *output = [self outputInWorkdirForArguments:arguments retValue:&retValue];
	if (retValue) {
		NSString *message = [NSString stringWithFormat:@"There was an error creating the branch '%@' at %@ '%@'.", branchName, [ref refishType], [ref shortName]];
		[self.windowController showErrorSheetTitle:@"Create Branch failed!" message:message arguments:arguments output:output];
		return NO;
	}

	[self reloadRefs];
	return YES;
}

- (BOOL) createTag:(NSString *)tagName message:(NSString *)message atRefish:(id <PBGitRefish>)target
{
	if (!tagName)
		return NO;

	int retValue = 1;
	NSArray *arguments;
	
	// Create annotated tag if message is provided, otherwise lightweight tag
	if (message && message.length > 0) {
		arguments = [NSArray arrayWithObjects:@"tag", @"-a", tagName, @"-m", message, [target refishName], nil];
	} else {
		arguments = [NSArray arrayWithObjects:@"tag", tagName, [target refishName], nil];
	}
	
	NSString *output = [self outputForArguments:arguments retValue:&retValue];
	if (retValue) {
		NSString *errorMessage = [NSString stringWithFormat:@"There was an error creating the tag '%@' at %@ '%@'.", tagName, [target refishType], [target shortName]];
		[self.windowController showErrorSheetTitle:@"Create Tag failed!" message:errorMessage arguments:arguments output:output];
		return NO;
	}

	[self reloadRefs];
	return YES;
}

- (BOOL) deleteRef:(PBGitRef *)ref
{
	if (!ref)
		return NO;

	if ([ref refishType] == kGitXRemoteType)
		return NO;

	int retValue = 1;
	NSArray *arguments = [NSArray arrayWithObjects:@"update-ref", @"-d", [ref ref], nil];
	NSString * output = [self outputForArguments:arguments retValue:&retValue];
	if (retValue) {
		NSString *message = [NSString stringWithFormat:@"There was an error deleting the ref: %@\n\n", [ref shortName]];
		[self.windowController showErrorSheetTitle:@"Delete ref failed!" message:message arguments:arguments output:output];
		return NO;
	}

	[self removeBranch:[[PBGitRevSpecifier alloc] initWithRef:ref]];
	PBGitCommit *commit = [self commitForRef:ref];
	[commit removeRef:ref];

	[self reloadRefs];
	return YES;
}


#pragma mark GitX Scripting

- (void)handleRevListArguments:(NSArray *)arguments inWorkingDirectory:(NSURL *)workingDirectory
{
	if (![arguments count])
		return;

	PBGitRevSpecifier *revListSpecifier = nil;

	// the argument may be a branch or tag name but will probably not be the full reference
	if ([arguments count] == 1) {
		PBGitRef *refArgument = [self refForName:[arguments lastObject]];
		if (refArgument) {
			revListSpecifier = [[PBGitRevSpecifier alloc] initWithRef:refArgument];
			revListSpecifier.workingDirectory = workingDirectory;
		}
	}

	if (!revListSpecifier) {
		revListSpecifier = [[PBGitRevSpecifier alloc] initWithParameters:arguments];
		revListSpecifier.workingDirectory = workingDirectory;
	}

	self.currentBranch = [self addBranch:revListSpecifier];
	[PBGitDefaults setShowStageView:NO];
	[self.windowController showHistoryView:self];
}

- (void)handleBranchFilterEventForFilter:(PBGitXBranchFilterType)filter additionalArguments:(NSMutableArray *)arguments inWorkingDirectory:(NSURL *)workingDirectory
{
	self.currentBranchFilter = filter;
	[PBGitDefaults setShowStageView:NO];
	[self.windowController showHistoryView:self];

	// treat any additional arguments as a rev-list specifier
	if ([arguments count] > 1) {
		[arguments removeObjectAtIndex:0];
		[self handleRevListArguments:arguments inWorkingDirectory:workingDirectory];
	}
}

- (void)handleGitXScriptingArguments:(NSAppleEventDescriptor *)argumentsList inWorkingDirectory:(NSURL *)workingDirectory
{
	NSMutableArray *arguments = [NSMutableArray array];
	uint argumentsIndex = 1; // AppleEvent list descriptor's are one based
	while(1) {
		NSAppleEventDescriptor *arg = [argumentsList descriptorAtIndex:argumentsIndex++];
		if (arg)
			[arguments addObject:[arg stringValue]];
		else
			break;
	}

	if (![arguments count])
		return;

	NSString *firstArgument = [arguments objectAtIndex:0];

	if ([firstArgument isEqualToString:@"-c"] || [firstArgument isEqualToString:@"--commit"]) {
		[PBGitDefaults setShowStageView:YES];
		[self.windowController showCommitView:self];
		return;
	}

	if ([firstArgument isEqualToString:@"--all"]) {
		[self handleBranchFilterEventForFilter:kGitXAllBranchesFilter additionalArguments:arguments inWorkingDirectory:workingDirectory];
		return;
	}

	if ([firstArgument isEqualToString:@"--local"]) {
		[self handleBranchFilterEventForFilter:kGitXLocalRemoteBranchesFilter additionalArguments:arguments inWorkingDirectory:workingDirectory];
		return;
	}

	if ([firstArgument isEqualToString:@"--branch"]) {
		[self handleBranchFilterEventForFilter:kGitXSelectedBranchFilter additionalArguments:arguments inWorkingDirectory:workingDirectory];
		return;
	}

	// if the argument is not a known command then treat it as a rev-list specifier
	[self handleRevListArguments:arguments inWorkingDirectory:workingDirectory];
}

// for the scripting bridge
- (void)findInModeScriptCommand:(NSScriptCommand *)command
{
	NSDictionary *arguments = [command arguments];
	NSString *searchString = [arguments objectForKey:kGitXFindSearchStringKey];
	if (searchString) {
		NSInteger mode = [[arguments objectForKey:kGitXFindInModeKey] integerValue];
		[PBGitDefaults setShowStageView:NO];
		[self.windowController showHistoryView:self];
		[self.windowController setHistorySearch:searchString mode:mode];
	}
}


#pragma mark low level

- (int) returnValueForCommand:(NSString *)cmd
{
	int i;
	[self outputForCommand:cmd retValue: &i];
	return i;
}

- (NSFileHandle*) handleForArguments:(NSArray *)args
{
	NSString* gitDirArg = [@"--git-dir=" stringByAppendingString:self.gitURL.path];
	NSMutableArray* arguments =  [NSMutableArray arrayWithObject: gitDirArg];
	[arguments addObjectsFromArray: args];
	return [PBEasyPipe handleForCommand:[PBGitBinary path] withArgs:arguments];
}

- (NSFileHandle*) handleInWorkDirForArguments:(NSArray *)args
{
	NSString* gitDirArg = [@"--git-dir=" stringByAppendingString:self.gitURL.path];
	NSMutableArray* arguments =  [NSMutableArray arrayWithObject: gitDirArg];
	[arguments addObjectsFromArray: args];
	return [PBEasyPipe handleForCommand:[PBGitBinary path] withArgs:arguments inDir:[self workingDirectory]];
}

- (NSFileHandle*) handleForCommand:(NSString *)cmd
{
	NSArray* arguments = [cmd componentsSeparatedByString:@" "];
	return [self handleForArguments:arguments];
}

- (NSString*) outputForCommand:(NSString *)cmd
{
	NSArray* arguments = [cmd componentsSeparatedByString:@" "];
	return [self outputForArguments: arguments];
}

- (NSString*) outputForCommand:(NSString *)str retValue:(int *)ret;
{
	NSArray* arguments = [str componentsSeparatedByString:@" "];
	return [self outputForArguments: arguments retValue: ret];
}

- (NSString*) outputForArguments:(NSArray*) arguments
{
	return [PBEasyPipe outputForCommand:[PBGitBinary path] withArgs:arguments inDir: self.fileURL.path];
}

- (NSString*) outputInWorkdirForArguments:(NSArray*) arguments
{
	return [PBEasyPipe outputForCommand:[PBGitBinary path] withArgs:arguments inDir: [self workingDirectory]];
}

- (NSString*) outputInWorkdirForArguments:(NSArray *)arguments retValue:(int *)ret
{
	return [PBEasyPipe outputForCommand:[PBGitBinary path] withArgs:arguments inDir:[self workingDirectory] retValue: ret];
}

- (NSString*) outputForArguments:(NSArray *)arguments retValue:(int *)ret
{
	return [PBEasyPipe outputForCommand:[PBGitBinary path] withArgs:arguments inDir: self.fileURL.path retValue: ret];
}

- (NSString*) outputForArguments:(NSArray *)arguments inputString:(NSString *)input retValue:(int *)ret
{
	return [PBEasyPipe outputForCommand:[PBGitBinary path]
							   withArgs:arguments
								  inDir:[self workingDirectory]
							inputString:input
							   retValue: ret];
}

- (NSString *)outputForArguments:(NSArray *)arguments inputString:(NSString *)input byExtendingEnvironment:(NSDictionary *)dict retValue:(int *)ret
{
	return [PBEasyPipe outputForCommand:[PBGitBinary path]
							   withArgs:arguments
								  inDir:[self workingDirectory]
				 byExtendingEnvironment:dict
							inputString:input
							   retValue: ret];
}

- (BOOL)executeHook:(NSString *)name output:(NSString **)output
{
	return [self executeHook:name withArgs:[NSArray array] output:output];
}

- (BOOL)executeHook:(NSString *)name withArgs:(NSArray *)arguments output:(NSString **)output
{
	NSString *hookPath = [[[[self gitURL] path] stringByAppendingPathComponent:@"hooks"] stringByAppendingPathComponent:name];
	if (![[NSFileManager defaultManager] isExecutableFileAtPath:hookPath])
		return TRUE;

	NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
		[self gitURL].path, @"GIT_DIR",
		[[self gitURL].path stringByAppendingPathComponent:@"index"], @"GIT_INDEX_FILE",
		nil
	];

	int ret = 1;
	NSString *_output =	[PBEasyPipe outputForCommand:hookPath withArgs:arguments inDir:[self workingDirectory] byExtendingEnvironment:info inputString:nil retValue:&ret];

	if (output)
		*output = _output;

	return ret == 0;
}

- (NSString *)parseReference:(NSString *)reference
{
	int ret = 1;
	NSString *ref = [self outputForArguments:[NSArray arrayWithObjects: @"rev-parse", @"--verify", reference, nil] retValue: &ret];
	if (ret)
		return nil;

	return ref;
}

- (NSString*) parseSymbolicReference:(NSString*) reference
{
	NSString* ref = [self outputForArguments:[NSArray arrayWithObjects: @"symbolic-ref", @"-q", reference, nil]];
	if ([ref hasPrefix:@"refs/"])
		return ref;

	return nil;
}

@end
