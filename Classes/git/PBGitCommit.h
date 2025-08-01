//
//  PBGitCommit.h
//  GitTest
//
//  Created by Pieter de Bie on 13-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PBGitRefish.h" // for @protocol PBGitRefish
#import "GTOID+JavaScript.h" // for GTOID stub

@class PBGitRepository;
@class PBGitTree;
@class PBGitRef;
@class PBGraphCellInfo;

extern NSString * const kGitXCommitType;


@interface PBGitCommit : NSObject <PBGitRefish>

@property (nonatomic, weak, readonly) PBGitRepository* repository;

@property (nonatomic, strong, readonly) GTOID *sha;

@property (nonatomic, strong, readonly) NSDate *date;
@property (nonatomic, strong, readonly) NSString *subject;
@property (nonatomic, strong, readonly) NSString *author;
@property (nonatomic, strong, readonly) NSString *committer;
@property (nonatomic, strong, readonly) NSString *details;
@property (nonatomic, strong, readonly) NSString *patch;
@property (nonatomic, strong, readonly) NSString *realSHA;
@property (nonatomic, strong, readonly) NSString *SVNRevision;

@property (nonatomic, strong, readonly) NSArray *parents;
@property  NSMutableArray* refs;

@property (nonatomic, assign)	char sign;
@property (nonatomic, strong) PBGraphCellInfo *lineInfo;

@property (nonatomic, readonly) PBGitTree* tree;
@property (readonly) NSArray* treeContents;


// REPLACE WITH GIT EXEC - Remove GTCommit dependency
- (id)initWithRepository:(PBGitRepository *)repo andSHA:(NSString *)sha;

- (void) addRef:(PBGitRef *)ref;
- (void) removeRef:(id)ref;
- (BOOL) hasRef:(PBGitRef *)ref;

- (NSString *)realSha;
- (BOOL) isOnSameBranchAs:(PBGitCommit *)other;
- (BOOL) isOnHeadBranch;

// <PBGitRefish>
- (NSString *) refishName;
- (NSString *) shortName;
- (NSString *) refishType;

@end
