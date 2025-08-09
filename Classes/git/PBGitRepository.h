//
//  PBGitRepository.h
//  GitTest
//
//  Created by Pieter de Bie on 13-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PBGitHistoryList;
@class PBGitRevSpecifier;
@protocol PBGitRefish;
@class PBGitRef;
@class GTConfiguration;

extern NSString* PBGitRepositoryErrorDomain;
extern NSString *PBGitRepositoryDocumentType;

// Standardized Git Error Codes
typedef NS_ENUM(NSInteger, PBGitErrorCode) {
    PBGitErrorCommandFailed = 1001,
    PBGitErrorInvalidRepository = 1002,
    PBGitErrorInvalidRef = 1003,
    PBGitErrorGitNotFound = 1004,
    PBGitErrorInvalidArguments = 1005
};

typedef enum branchFilterTypes {
	kGitXAllBranchesFilter = 0,
	kGitXLocalRemoteBranchesFilter,
	kGitXSelectedBranchFilter
} PBGitXBranchFilterType;

static NSString * PBStringFromBranchFilterType(PBGitXBranchFilterType type) {
    switch (type) {
        case kGitXAllBranchesFilter:
            return @"All";
            break;
        case kGitXLocalRemoteBranchesFilter:
            return @"Local";
            break;
        case kGitXSelectedBranchFilter:
            return @"Selected";
            break;
        default:
            break;
    }
    return @"Not a branch filter type";
}

@class PBGitWindowController;
@class PBGitCommit;
@class PBCommitID;
@interface PBGitRepository : NSDocument {
	__strong PBGitRevSpecifier *_headRef; // Caching
	__strong PBCommitID* _headSha;
	__strong NSString* _cachedWorkingDirectory; // Cache for workingDirectory to avoid repeated git calls
}


@property (assign) BOOL hasChanged;
@property (assign) NSInteger currentBranchFilter;

@property (readonly, strong) PBGitWindowController *windowController;
@property (readonly, getter = getIndexURL) NSURL* indexURL;

@property (nonatomic, strong) PBGitHistoryList *revisionList;
@property (nonatomic, readonly, strong) NSArray* branches;
@property (nonatomic, strong) NSMutableOrderedSet* branchesSet;
@property (nonatomic, strong) PBGitRevSpecifier* currentBranch;
@property (nonatomic, strong) NSMutableDictionary* refs;

@property (nonatomic, strong) NSMutableArray* submodules;

- (BOOL) checkoutRefish:(id <PBGitRefish>)ref;
- (BOOL) mergeWithRefish:(id <PBGitRefish>)ref;
- (BOOL) cherryPickRefish:(id <PBGitRefish>)ref;
- (BOOL) rebaseBranch:(id <PBGitRefish>)branch onRefish:(id <PBGitRefish>)upstream;
- (BOOL) createBranch:(NSString *)branchName atRefish:(id <PBGitRefish>)ref;
- (BOOL) createTag:(NSString *)tagName message:(NSString *)message atRefish:(id <PBGitRefish>)commitSHA;
- (BOOL) deleteRef:(PBGitRef *)ref;

- (NSURL *) gitURL ;

// Centralized Git Execution Methods (New Standardized Interface)
- (NSString *)executeGitCommand:(NSArray *)arguments error:(NSError **)error;
- (NSString *)executeGitCommand:(NSArray *)arguments inWorkingDir:(BOOL)useWorkDir error:(NSError **)error;
- (NSString *)executeGitCommand:(NSArray *)arguments withInput:(NSString *)input error:(NSError **)error;
- (NSString *)executeGitCommand:(NSArray *)arguments withInput:(NSString *)input environment:(NSDictionary *)env error:(NSError **)error;

// Handle-based methods (for streaming data operations)
- (NSFileHandle*) handleForArguments:(NSArray*) args;
- (NSFileHandle *) handleInWorkDirForArguments:(NSArray *)args;
- (BOOL)executeHook:(NSString *)name output:(NSString **)output;
- (BOOL)executeHook:(NSString *)name withArgs:(NSArray*) arguments output:(NSString **)output;

- (NSString *)workingDirectory;
- (NSString *) projectName;
- (NSString *)gitIgnoreFilename;
- (BOOL)isBareRepository;


- (void) reloadRefs;
- (void) lazyReload;
- (PBGitRevSpecifier*)headRef;
- (PBCommitID *)headSHA;
- (PBGitCommit *)headCommit;
- (PBCommitID *)shaForRef:(PBGitRef *)ref;
- (PBGitCommit *)commitForRef:(PBGitRef *)ref;
- (PBGitCommit *)commitForSHA:(PBCommitID *)sha;
- (BOOL)isOnSameBranch:(PBCommitID *)baseSHA asSHA:(PBCommitID *)testSHA;
- (BOOL)isSHAOnHeadBranch:(PBCommitID *)testSHA;
- (BOOL)isRefOnHeadBranch:(PBGitRef *)testRef;
- (BOOL)checkRefFormat:(NSString *)refName;
- (BOOL)refExists:(PBGitRef *)ref;
- (PBGitRef *)refForName:(NSString *)name;

- (NSArray *) remotes;
- (BOOL) hasRemotes;
- (PBGitRef *) remoteRefForBranch:(PBGitRef *)branch error:(NSError **)error;

- (void) readCurrentBranch;
- (PBGitRevSpecifier*) addBranch: (PBGitRevSpecifier*) rev;
- (BOOL)removeBranch:(PBGitRevSpecifier *)rev;

- (NSString*) parseSymbolicReference:(NSString*) ref;
- (NSString*) parseReference:(NSString*) ref;

- (void) forceUpdateRevisions;
- (NSURL*) getIndexURL;

// for the scripting bridge
- (void)findInModeScriptCommand:(NSScriptCommand *)command;

@end
