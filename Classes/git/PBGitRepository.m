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
#import "GitRepoFinder.h"
#import "PBGitHistoryList.h"
#import "PBGitSVSubmoduleItem.h"


NSString *PBGitRepositoryDocumentType = @"Git Repository";

@interface PBGitRepository ()
{
	NSMutableDictionary *refToSHAMapping; // Maps ref strings to GTOID objects
}

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
	_cachedWorkingDirectory = nil;
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
    NSError *error = nil;
    NSString *symbolicRef = [self executeGitCommand:@[@"symbolic-ref", @"HEAD"] error:&error];
    
    // If symbolic-ref fails, HEAD is detached
    if (error || !symbolicRef) {
        return [NSString localizedStringWithFormat:@"%@ (detached HEAD)", self.projectName];
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

- (void)showWindows
{
	[super showWindows];
}

#pragma mark -
#pragma mark Properties/General methods

- (NSURL *)getIndexURL
{
	NSError *error = nil;
	NSString *indexPath = [self executeGitCommand:@[@"rev-parse", @"--git-path", @"index"] error:&error];
	
	if (error || !indexPath) {
		// Fallback to standard path if git command fails
		indexPath = [[self workingDirectory] stringByAppendingPathComponent:@".git/index"];
		return [NSURL fileURLWithPath:indexPath];
	}
	
	// Convert relative path to absolute path
	if (![indexPath isAbsolutePath]) {
		indexPath = [[self workingDirectory] stringByAppendingPathComponent:indexPath];
	}
	
	return [NSURL fileURLWithPath:indexPath];
}

- (BOOL)isBareRepository
{
    NSError *error = nil;
    NSString *result = [self executeGitCommand:@[@"config", @"--get", @"core.bare"] error:&error];
    
    if (error || !result) {
        return NO;
    }
    
    return [result isEqualToString:@"true"];
}


- (NSURL *)gitURL {
	NSError *error = nil;
	NSString *gitPath = [self executeGitCommand:@[@"rev-parse", @"--git-dir"] error:&error];
	
	if (error || !gitPath) {
		// Fallback to standard path if git command fails
		gitPath = [[self workingDirectory] stringByAppendingPathComponent:@".git"];
		return [NSURL fileURLWithPath:gitPath];
	}
	
	// Convert relative path to absolute path
	if (![gitPath isAbsolutePath]) {
		gitPath = [[self workingDirectory] stringByAppendingPathComponent:gitPath];
	}
	
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
	refToSHAMapping = [NSMutableDictionary dictionary];
	
	// Use git for-each-ref to enumerate all references with their commit SHAs
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/usr/bin/git";
	task.arguments = @[@"for-each-ref", @"--format=%(refname)%09%(objecttype)%09%(objectname)"];
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
					// Format: refname<tab>objecttype<tab>objectname
					NSArray *components = [line componentsSeparatedByString:@"\t"];
					if ([components count] >= 3) {
						NSString *referenceName = [components objectAtIndex:0];
						NSString *objectType = [components objectAtIndex:1];
						NSString *commitSHA = [components objectAtIndex:2];
						
						// Skip symbolic references like origin/HEAD that point to other refs
						if ([objectType isEqualToString:@"commit"] || [objectType isEqualToString:@"tag"]) {
							PBGitRef* gitRef = [PBGitRef refFromString:referenceName];
							PBGitRevSpecifier* revSpec = [[PBGitRevSpecifier alloc] initWithRef:gitRef];
							[self addBranch:revSpec];
							[oldBranches removeObject:revSpec];
							
							// Add ref to commit SHA mapping for branch tags
							if (commitSHA && [commitSHA length] >= 40) { // Ensure valid SHA
								GTOID *sha = [GTOID oidWithSHA:commitSHA];
								if (sha) {
									NSMutableArray *refsForCommit = self->refs[sha];
									if (!refsForCommit) {
										refsForCommit = [NSMutableArray array];
										self->refs[sha] = refsForCommit;
									}
									[refsForCommit addObject:gitRef];
									
									// Also store ref->SHA mapping for efficient lookup
									refToSHAMapping[referenceName] = sha;
								}
							}
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
	
	// First try the efficient mapping from reloadRefs
	GTOID *sha = refToSHAMapping[ref.ref];
	if (sha) {
		return sha;
	}
	
	// Fallback: search through the refs dictionary (less efficient but handles edge cases)
	for (GTOID *existingSha in refs)
	{
		NSMutableArray *refsForSha = [refs objectForKey:existingSha];
		for (PBGitRef *existingRef in refsForSha)
		{
			if ([existingRef isEqualToRef:ref])
			{
				return existingSha;
			}
		}
    }
    
	// Last resort: use git rev-parse (should rarely be needed now)
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
				GTOID *fallbackSha = [GTOID oidWithSHA:shaString];
				// Cache it for future lookups
				if (fallbackSha) {
					refToSHAMapping[ref.ref] = fallbackSha;
				}
				return fallbackSha;
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
	NSError *error = nil;
	[self executeGitCommand:@[@"check-ref-format", refName] error:&error];
	
	// git check-ref-format returns 0 for valid refs
	if (error) {
		// Check if it's a command failure (invalid format) vs other error
		if (error.code == PBGitErrorCommandFailed) {
			return NO;
		}
		// If git is not available, assume valid
		return YES;
	}
	
	return YES;
}

- (BOOL) refExists:(PBGitRef *)ref
{
	NSError *error = nil;
	[self executeGitCommand:@[@"show-ref", @"--verify", @"--quiet", ref.ref] error:&error];
	
	// git show-ref --verify returns 0 if ref exists
	if (error) {
		// Command failure means ref doesn't exist
		return NO;
	}
	
	return YES;
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

	NSIndexSet *newIndex = [NSIndexSet indexSetWithIndex:(NSUInteger)[self.branches count]];
	[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:newIndex forKey:@"branches"];

    [self.branchesSet addObject:branch];

	[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:newIndex forKey:@"branches"];
	return branch;
}

- (BOOL) removeBranch:(PBGitRevSpecifier *)branch
{
    if ([self.branchesSet containsObject:branch]) {
        NSIndexSet *oldIndex = [NSIndexSet indexSetWithIndex:(NSUInteger)[self.branches indexOfObject:branch]];
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
	// Return cached value if available
	if (_cachedWorkingDirectory) {
		return _cachedWorkingDirectory;
	}
	
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
				_cachedWorkingDirectory = [workdir stringByStandardizingPath];
				return _cachedWorkingDirectory;
			}
		}
	}
	@catch (NSException *exception) {
		// Git not available or other error, fall back
	}
	
	// Fallback to original logic and cache it
	_cachedWorkingDirectory = self.fileURL.path;
	return _cachedWorkingDirectory;
}

#pragma mark Remotes

- (NSArray *) remotes
{
	NSError *error = nil;
	NSString *remotes = [self executeGitCommand:@[@"remote"] error:&error];
	if (error || [remotes isEqualToString:@""])
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


#pragma mark Repository commands



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


#pragma mark Centralized Git Execution

- (NSString *)executeGitCommand:(NSArray *)arguments error:(NSError **)error
{
    return [self executeGitCommand:arguments inWorkingDir:NO error:error];
}

- (NSString *)executeGitCommand:(NSArray *)arguments inWorkingDir:(BOOL)useWorkDir error:(NSError **)error
{
    // For now, we always use working directory since that's the current behavior
    // This parameter is for future enhancement to support git-dir operations
    return [self executeGitCommand:arguments withInput:nil environment:nil error:error];
}

- (NSString *)executeGitCommand:(NSArray *)arguments withInput:(NSString *)input error:(NSError **)error
{
    return [self executeGitCommand:arguments withInput:input environment:nil error:error];
}

- (NSString *)executeGitCommand:(NSArray *)arguments withInput:(NSString *)input environment:(NSDictionary *)env error:(NSError **)error
{
    // Validate arguments
    if (!arguments || [arguments count] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PBGitRepositoryErrorDomain
                                         code:PBGitErrorInvalidArguments
                                     userInfo:@{NSLocalizedDescriptionKey: @"Git command arguments cannot be empty"}];
        }
        return nil;
    }
    
    // Check that git binary is available
    NSString *gitPath = [PBGitBinary path];
    if (!gitPath) {
        if (error) {
            *error = [NSError errorWithDomain:PBGitRepositoryErrorDomain
                                         code:PBGitErrorGitNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Git binary not found",
                                               NSLocalizedRecoverySuggestionErrorKey: [PBGitBinary notFoundError]}];
        }
        return nil;
    }
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = gitPath;
    task.arguments = arguments;
    
    // Set working directory 
    NSString *workDir = [self workingDirectory];
    if (workDir) {
        task.currentDirectoryPath = workDir;
    }
    
    // Prepare environment
    NSMutableDictionary *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
    [environment removeObjectsForKeys:@[@"MallocStackLogging", @"MallocStackLoggingNoCompact", @"NSZombieEnabled"]];
    if (env) {
        [environment addEntriesFromDictionary:env];
    }
    task.environment = environment;
    
    // Set up pipes
    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    task.standardOutput = outputPipe;
    task.standardError = errorPipe;
    
    // Handle input if provided
    if (input) {
        NSPipe *inputPipe = [NSPipe pipe];
        task.standardInput = inputPipe;
    }
    
    // Debug logging
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"Show Debug Messages"]) {
        NSLog(@"Executing git command: %@ %@ in %@", gitPath, [arguments componentsJoinedByString:@" "], workDir);
    }
    
    NSString *output = nil;
    NSString *errorOutput = nil;
    
    @try {
        [task launch];
        
        // Write input if provided
        if (input) {
            NSFileHandle *inputHandle = [[task standardInput] fileHandleForWriting];
            [inputHandle writeData:[input dataUsingEncoding:NSUTF8StringEncoding]];
            [inputHandle closeFile];
        }
        
        // Read output
        NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
        NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
        
        [task waitUntilExit];
        
        // Convert output to string
        output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
        if (!output) {
            output = [[NSString alloc] initWithData:outputData encoding:NSISOLatin1StringEncoding];
        }
        
        errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
        if (!errorOutput) {
            errorOutput = [[NSString alloc] initWithData:errorData encoding:NSISOLatin1StringEncoding];
        }
        
        // Strip trailing newlines
        if ([output hasSuffix:@"\n"]) {
            output = [output substringToIndex:[output length] - 1];
        }
        
        // Check for command failure
        if (task.terminationStatus != 0) {
            if (error) {
                NSString *errorMessage = [NSString stringWithFormat:@"Git command failed with exit code %d", task.terminationStatus];
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                                 errorMessage, NSLocalizedDescriptionKey,
                                                 [NSString stringWithFormat:@"Command: git %@", [arguments componentsJoinedByString:@" "]], @"GitCommand",
                                                 @(task.terminationStatus), @"ExitCode",
                                                 nil];
                
                if (errorOutput && [errorOutput length] > 0) {
                    [userInfo setObject:errorOutput forKey:NSLocalizedRecoverySuggestionErrorKey];
                }
                
                *error = [NSError errorWithDomain:PBGitRepositoryErrorDomain
                                             code:PBGitErrorCommandFailed
                                         userInfo:userInfo];
            }
            return nil;
        }
        
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:PBGitRepositoryErrorDomain
                                         code:PBGitErrorCommandFailed
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Git command execution failed: %@", exception.reason],
                                               @"Exception": exception.reason ?: @"Unknown exception"}];
        }
        return nil;
    }
    
    return output;
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
