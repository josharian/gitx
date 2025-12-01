//
//  PBGitIndex.m
//  GitX
//
//  Created by Pieter de Bie on 9/12/09.
//  Copyright 2009 Pieter de Bie. All rights reserved.
//

#import "PBGitIndex.h"
#import "GitX-Swift.h"
#import "PBGitRepository.h"

NSString *PBGitIndexIndexRefreshStatus = @"PBGitIndexIndexRefreshStatus";
NSString *PBGitIndexIndexRefreshFailed = @"PBGitIndexIndexRefreshFailed";
NSString *PBGitIndexFinishedIndexRefresh = @"PBGitIndexFinishedIndexRefresh";

NSString *PBGitIndexIndexUpdated = @"GBGitIndexIndexUpdated";

NSString *PBGitIndexCommitStatus = @"PBGitIndexCommitStatus";
NSString *PBGitIndexCommitFailed = @"PBGitIndexCommitFailed";
NSString *PBGitIndexCommitHookFailed = @"PBGitIndexCommitHookFailed";
NSString *PBGitIndexFinishedCommit = @"PBGitIndexFinishedCommit";

NSString *PBGitIndexAmendMessageAvailable = @"PBGitIndexAmendMessageAvailable";
NSString *PBGitIndexOperationFailed = @"PBGitIndexOperationFailed";

static const NSUInteger kPBGitIndexDiffPreviewTruncationLimit = 16384;

@interface PBGitIndex ()

// Returns the tree to compare the index to, based
// on whether amend is set or not.
- (NSString *)parentTree;
- (void)postCommitUpdate:(NSString *)update;
- (void)postCommitFailure:(NSString *)reason;
- (void)postCommitHookFailure:(NSString *)reason;
- (void)postIndexChange;
- (void)postOperationFailed:(NSString *)description;
@end

@implementation PBGitIndex

+ (NSUInteger)diffPreviewTruncationLimit {
  return kPBGitIndexDiffPreviewTruncationLimit;
}

- (id)initWithRepository:(PBGitRepository *)theRepository {
  if (!(self = [super init]))
    return nil;

  NSAssert(theRepository, @"PBGitIndex requires a repository");

  repository = theRepository;
  NSString *workingPath = theRepository.workingDirectory;
  if (workingPath) {
    workingDirectory = [NSURL fileURLWithPath:workingPath];
  }
  files = [NSMutableArray array];

  return self;
}

- (NSArray *)indexChanges {
  return files;
}

- (void)setAmend:(BOOL)newAmend {
  if (newAmend == amend)
    return;

  amend = newAmend;
  amendEnvironment = nil;

  [self refresh];

  if (!newAmend)
    return;

  // If we amend, we want to keep the author information for the previous commit
  // We do this by reading in the previous commit, and storing the information
  // in a dictionary. This dictionary will then later be read by [self commit:]
  NSError *error = nil;
  NSString *message = [repository
      executeGitCommand:[NSArray arrayWithObjects:@"cat-file", @"commit",
                                                  @"HEAD", nil]
                  error:&error];
  NSArray *match =
      [message substringsMatchingRegularExpression:
                   @"\nauthor ([^\n]*) <([^\n>]*)> ([0-9]+[^\n]*)\n"
                                             count:3
                                           options:0
                                            ranges:nil
                                             error:nil];
  if (match)
    amendEnvironment =
        [NSDictionary dictionaryWithObjectsAndKeys:[match objectAtIndex:1],
                                                   @"GIT_AUTHOR_NAME",
                                                   [match objectAtIndex:2],
                                                   @"GIT_AUTHOR_EMAIL",
                                                   [match objectAtIndex:3],
                                                   @"GIT_AUTHOR_DATE", nil];

  // Find the commit message
  NSRange r = [message rangeOfString:@"\n\n"];
  if (r.location != NSNotFound) {
    NSString *commitMessage = [message substringFromIndex:r.location + 2];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:PBGitIndexAmendMessageAvailable
                      object:self
                    userInfo:[NSDictionary dictionaryWithObject:commitMessage
                                                         forKey:@"message"]];
  }
}

- (BOOL)amend {
  return amend;
}

- (void)refresh {
  // Cancel any in-progress refresh
  refreshStatus = 0;

  // Ask Git to refresh the index first
  [repository executeGitCommandAsync:@[@"update-index", @"-q", @"--unmerged", @"--ignore-missing", @"--refresh"]
                          completion:^(NSString *output, NSString *error, int exitCode) {
    if (exitCode != 0) {
      [[NSNotificationCenter defaultCenter]
          postNotificationName:PBGitIndexIndexRefreshFailed
                        object:self
                      userInfo:@{@"description": @"update-index failed"}];
      return;
    }

    [[NSNotificationCenter defaultCenter]
        postNotificationName:PBGitIndexIndexRefreshStatus
                      object:self
                    userInfo:@{@"description": @"update-index success"}];

    if ([repository isBareRepository]) {
      return;
    }

    // Now run the three index queries in parallel
    [self refreshIndexContents];
  }];
}

- (void)refreshIndexContents {
  NSString *parentTree = [self parentTree];

  // Run all three queries in parallel:
  // 0: Other files (untracked, not ignored)
  // 1: Unstaged files (diff-files)
  // 2: Staged files (diff-index)
  NSArray *commands = @[
    @[@"ls-files", @"--others", @"--exclude-standard", @"-z"],
    @[@"diff-files", @"-z"],
    @[@"diff-index", @"--cached", @"-z", parentTree]
  ];

  [repository executeGitCommandsAsync:commands completion:^(NSArray<NSDictionary *> *results) {
    // Process "other" files (untracked)
    NSDictionary *otherResult = results[0];
    NSArray *otherLines = [self linesFromOutput:otherResult[@"output"]];
    NSMutableDictionary *otherDict = [[NSMutableDictionary alloc] initWithCapacity:[otherLines count]];
    NSArray *fakeStatus = @[@":000000", @"100644",
                           @"0000000000000000000000000000000000000000",
                           @"0000000000000000000000000000000000000000", @"A"];
    for (NSString *path in otherLines) {
      if ([path length] > 0) {
        [otherDict setObject:fakeStatus forKey:path];
      }
    }
    [self addFilesFromDictionary:otherDict staged:NO tracked:NO];

    // Process unstaged files
    NSDictionary *unstagedResult = results[1];
    NSArray *unstagedLines = [self linesFromOutput:unstagedResult[@"output"]];
    NSMutableDictionary *unstagedDict = [self dictionaryForLines:unstagedLines];
    [self addFilesFromDictionary:unstagedDict staged:NO tracked:YES];

    // Process staged files
    NSDictionary *stagedResult = results[2];
    NSArray *stagedLines = [self linesFromOutput:stagedResult[@"output"]];
    NSMutableDictionary *stagedDict = [self dictionaryForLines:stagedLines];
    [self addFilesFromDictionary:stagedDict staged:YES tracked:YES];

    // All done - clean up files with no changes
    [self finalizeRefresh];
  }];
}

- (NSArray *)linesFromOutput:(NSString *)output {
  if (!output || [output length] == 0) {
    return @[];
  }
  // Strip trailing NUL if present
  if ([output hasSuffix:@"\0"]) {
    output = [output substringToIndex:[output length] - 1];
  }
  if ([output length] == 0) {
    return @[];
  }
  return [output componentsSeparatedByString:@"\0"];
}

- (void)finalizeRefresh {
  // Find all files that don't have either staged or unstaged changes and remove them
  NSMutableArray *deleteFiles = [NSMutableArray array];
  for (PBChangedFile *file in files) {
    if (!file.hasStagedChanges && !file.hasUnstagedChanges) {
      [deleteFiles addObject:file];
    }
  }

  if ([deleteFiles count]) {
    [self willChangeValueForKey:@"indexChanges"];
    for (PBChangedFile *file in deleteFiles) {
      [files removeObject:file];
    }
    [self didChangeValueForKey:@"indexChanges"];
  }

  [[NSNotificationCenter defaultCenter]
      postNotificationName:PBGitIndexFinishedIndexRefresh
                    object:self];
  [self postIndexChange];
}

- (NSString *)parentTree {
  NSString *parent = amend ? @"HEAD^" : @"HEAD";

  if (![repository parseReference:parent])
    // We don't have a head ref. Return the empty tree.
    return @"4b825dc642cb6eb9a060e54bf8d69288fbee4904";

  return parent;
}

// TODO: make Asynchronous
- (void)commitWithMessage:(NSString *)commitMessage andVerify:(BOOL)doVerify {
  NSMutableString *commitSubject = [@"commit: " mutableCopy];
  NSRange newLine = [commitMessage rangeOfString:@"\n"];
  if (newLine.location == NSNotFound)
    [commitSubject appendString:commitMessage];
  else
    [commitSubject
        appendString:[commitMessage substringToIndex:newLine.location]];

  NSString *commitMessageFile;
  commitMessageFile =
      [repository.gitURL.path stringByAppendingPathComponent:@"COMMIT_EDITMSG"];

  [commitMessage writeToFile:commitMessageFile
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];

  [self postCommitUpdate:@"Creating tree"];
  NSError *error = nil;
  NSString *tree = [repository
      executeGitCommand:[NSArray arrayWithObjects:@"write-tree", nil]
                  error:&error];
  if ([tree length] != 40)
    return [self postCommitFailure:@"Creating tree failed"];

  NSMutableArray *arguments =
      [NSMutableArray arrayWithObjects:@"commit-tree", tree, nil];
  NSString *parent = amend ? @"HEAD^" : @"HEAD";
  if ([repository parseReference:parent]) {
    [arguments addObject:@"-p"];
    [arguments addObject:parent];
  }

  [self postCommitUpdate:@"Creating commit"];

  if (doVerify) {
    [self postCommitUpdate:@"Running hooks"];
    NSString *hookFailureMessage = nil;
    NSString *hookOutput = nil;
    if (![repository executeHook:@"pre-commit" output:&hookOutput]) {
      hookFailureMessage = [NSString
          stringWithFormat:@"Pre-commit hook failed%@%@",
                           [hookOutput length] > 0 ? @":\n" : @"", hookOutput];
    }

    if (![repository executeHook:@"commit-msg"
                        withArgs:[NSArray arrayWithObject:commitMessageFile]
                          output:nil]) {
      hookFailureMessage = [NSString
          stringWithFormat:@"Commit-msg hook failed%@%@",
                           [hookOutput length] > 0 ? @":\n" : @"", hookOutput];
    }

    if (hookFailureMessage != nil) {
      return [self postCommitHookFailure:hookFailureMessage];
    }
  }

  commitMessage = [NSString stringWithContentsOfFile:commitMessageFile
                                            encoding:NSUTF8StringEncoding
                                               error:nil];

  NSError *commitError = nil;
  NSString *commit = [repository executeGitCommand:arguments
                                         withInput:commitMessage
                                       environment:amendEnvironment
                                             error:&commitError];

  if (commitError || [commit length] != 40)
    return [self postCommitFailure:@"Could not create a commit object"];

  [self postCommitUpdate:@"Updating HEAD"];
  error = nil;
  [repository executeGitCommand:[NSArray arrayWithObjects:@"update-ref", @"-m",
                                                          commitSubject,
                                                          @"HEAD", commit, nil]
                          error:&error];
  if (error)
    return [self postCommitFailure:@"Could not update HEAD"];

  [self postCommitUpdate:@"Running post-commit hook"];

  BOOL success = [repository executeHook:@"post-commit" output:nil];
  NSMutableDictionary *userInfo = [NSMutableDictionary
      dictionaryWithObject:[NSNumber numberWithBool:success]
                    forKey:@"success"];
  NSString *description;
  if (success)
    description =
        [NSString stringWithFormat:@"Successfully created commit %@", commit];
  else
    description = [NSString
        stringWithFormat:
            @"Post-commit hook failed, but successfully created commit %@",
            commit];

  [userInfo setObject:description forKey:@"description"];
  [userInfo setObject:commit forKey:@"sha"];

  [[NSNotificationCenter defaultCenter]
      postNotificationName:PBGitIndexFinishedCommit
                    object:self
                  userInfo:userInfo];
  if (!success)
    return;

  repository.hasChanged = YES;

  amendEnvironment = nil;
  if (amend)
    self.amend = NO;
  else
    [self refresh];
}

- (void)postCommitUpdate:(NSString *)update {
  [[NSNotificationCenter defaultCenter]
      postNotificationName:PBGitIndexCommitStatus
                    object:self
                  userInfo:[NSDictionary dictionaryWithObject:update
                                                       forKey:@"description"]];
}

- (void)postCommitFailure:(NSString *)reason {
  [[NSNotificationCenter defaultCenter]
      postNotificationName:PBGitIndexCommitFailed
                    object:self
                  userInfo:[NSDictionary dictionaryWithObject:reason
                                                       forKey:@"description"]];
}

- (void)postCommitHookFailure:(NSString *)reason {
  [[NSNotificationCenter defaultCenter]
      postNotificationName:PBGitIndexCommitHookFailed
                    object:self
                  userInfo:[NSDictionary dictionaryWithObject:reason
                                                       forKey:@"description"]];
}

- (void)postOperationFailed:(NSString *)description {
  [[NSNotificationCenter defaultCenter]
      postNotificationName:PBGitIndexOperationFailed
                    object:self
                  userInfo:[NSDictionary dictionaryWithObject:description
                                                       forKey:@"description"]];
}

- (BOOL)stageFiles:(NSArray *)files {
  return [self updateIndexForFiles:files stage:YES];
}

- (BOOL)unstageFiles:(NSArray *)files {
  return [self updateIndexForFiles:files stage:NO];
}

// Unified staging/unstaging implementation.
// Processes files in chunks of 1000 to avoid NSPipe capacity limits.
- (BOOL)updateIndexForFiles:(NSArray *)files stage:(BOOL)stage {
  NSUInteger filesCount = [files count];
  if (filesCount == 0) {
    return YES;
  }

  NSArray *command = stage
      ? @[ @"update-index", @"--add", @"--remove", @"-z", @"--stdin" ]
      : @[ @"update-index", @"-z", @"--index-info" ];
  NSString *errorContext = stage ? @"staging" : @"unstaging";

  NSUInteger loopFrom = 0;
  while (loopFrom < filesCount) {
    NSUInteger loopTo = MIN(loopFrom + 1000, filesCount);

    NSMutableString *input = [NSMutableString string];
    for (NSUInteger i = loopFrom; i < loopTo; i++) {
      PBChangedFile *file = files[i];
      if (stage) {
        [input appendFormat:@"%@\0", file.path];
      } else {
        [input appendString:[file indexInfo]];
      }
    }

    NSError *error = nil;
    [repository executeGitCommand:command withInput:input error:&error];

    if (error) {
      [self postOperationFailed:
                [NSString stringWithFormat:@"Error in %@ files: %@",
                                           errorContext,
                                           error.localizedDescription]];
      return NO;
    }

    for (NSUInteger i = loopFrom; i < loopTo; i++) {
      PBChangedFile *file = files[i];
      file.hasUnstagedChanges = !stage;
      file.hasStagedChanges = stage;
    }

    loopFrom = loopTo;
  }

  [self postIndexChange];
  return YES;
}

- (void)discardChangesForFiles:(NSArray *)discardFiles {
  NSArray *paths = [discardFiles valueForKey:@"path"];
  NSString *input = [paths componentsJoinedByString:@"\0"];

  NSArray *arguments =
      [NSArray arrayWithObjects:@"checkout-index", @"--index", @"--quiet",
                                @"--force", @"-z", @"--stdin", nil];

  NSError *error = nil;
  [repository executeGitCommand:arguments withInput:input error:&error];

  if (error) {
    [self postOperationFailed:
              [NSString stringWithFormat:@"Discarding changes failed: %@",
                                         error.localizedDescription]];
    return;
  }

  for (PBChangedFile *file in discardFiles)
    if (file.status != PBChangedFileStatusNew)
      file.hasUnstagedChanges = NO;

  [self postIndexChange];
}

- (BOOL)applyPatch:(NSString *)hunk stage:(BOOL)stage reverse:(BOOL)reverse;
{
  NSMutableArray *array =
      [NSMutableArray arrayWithObjects:@"apply", @"--unidiff-zero", nil];
  if (stage)
    [array addObject:@"--cached"];
  if (reverse)
    [array addObject:@"--reverse"];

  NSError *error = nil;
  [repository executeGitCommand:array
                      withInput:hunk
                          error:&error];

  if (error) {
    NSString *errorDesc = error.localizedDescription ?: @"Unknown error";
    NSString *gitError = error.localizedRecoverySuggestion ?: @"(no stderr)";
    NSString *gitCommand = [error.userInfo objectForKey:@"GitCommand"] ?: @"";

    // Write full details to temp file for debugging
    NSString *tempDir = NSTemporaryDirectory();
    NSString *timestamp = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *tempPath = [tempDir stringByAppendingPathComponent:
      [NSString stringWithFormat:@"gitx-patch-error-%@.txt", timestamp]];

    NSString *fullDetails = [NSString stringWithFormat:
      @"GitX Patch Application Error\n"
      @"============================\n\n"
      @"Error: %@\n\n"
      @"Git stderr:\n%@\n\n"
      @"%@\n\n"
      @"Patch attempted:\n"
      @"----------------\n%@",
      errorDesc, gitError, gitCommand, hunk];

    [fullDetails writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSString *displayMessage = [NSString stringWithFormat:
      @"%@\n\n"
      @"Git error:\n%@\n\n"
      @"Full details written to:\n%@",
      errorDesc, gitError, tempPath];

    [self postOperationFailed:displayMessage];
    return NO;
  }

  // TODO: Try to be smarter about what to refresh
  [self refresh];
  return YES;
}

- (NSString *)diffForFile:(PBChangedFile *)file
                   staged:(BOOL)staged
             contextLines:(NSUInteger)context {
  return [self diffForFile:file
                    staged:staged
              contextLines:context
                 truncated:NULL];
}

- (NSString *)diffForFile:(PBChangedFile *)file
                   staged:(BOOL)staged
             contextLines:(NSUInteger)context
                truncated:(BOOL *)truncated {
  NSString *parameter = [NSString stringWithFormat:@"-U%lu", context];
  NSString *diff = nil;

  if (staged) {
    NSString *indexPath = [@":0:" stringByAppendingString:file.path];

    if (file.status == PBChangedFileStatusNew) {
      NSError *error = nil;
      diff = [repository executeGitCommand:@[ @"show", indexPath ]
                                     error:&error];
    } else {
      NSError *error = nil;
      diff = [repository executeGitCommand:@[
        @"diff-index", parameter, @"--cached", [self parentTree], @"--",
        file.path
      ]
                              inWorkingDir:YES
                                     error:&error];
    }
  } else {
    if (file.status == PBChangedFileStatusNew) {
      NSStringEncoding encoding;
      NSError *error = nil;
      NSString *path = [[repository workingDirectory]
          stringByAppendingPathComponent:file.path];
      diff = [NSString stringWithContentsOfFile:path
                                   usedEncoding:&encoding
                                          error:&error];
      if (error)
        diff = nil;
    } else {
      NSError *error = nil;
      diff = [repository
          executeGitCommand:@[ @"diff-files", parameter, @"--", file.path ]
               inWorkingDir:YES
                      error:&error];
    }
  }

  BOOL didTruncate = NO;
  if (diff && (file.status == PBChangedFileStatusNew ||
               file.status == PBChangedFileStatusDeleted)) {
    if ([diff length] > kPBGitIndexDiffPreviewTruncationLimit) {
      diff = [diff substringToIndex:kPBGitIndexDiffPreviewTruncationLimit];
      didTruncate = YES;
    }
  }

  if (truncated)
    *truncated = didTruncate;

  return diff;
}

- (void)postIndexChange {
  [[NSNotificationCenter defaultCenter]
      postNotificationName:PBGitIndexIndexUpdated
                    object:self];
}

- (void)addFilesFromDictionary:(NSMutableDictionary *)dictionary
                        staged:(BOOL)staged
                       tracked:(BOOL)tracked {
  // Iterate over all existing files
  for (PBChangedFile *file in files) {
    NSArray *fileStatus = [dictionary objectForKey:file.path];
    // Object found, this is still a cached / uncached thing
    if (fileStatus) {
      if (tracked) {
        NSString *mode = [[fileStatus objectAtIndex:0] substringFromIndex:1];
        NSString *sha = [fileStatus objectAtIndex:2];
        file.commitBlobSHA = sha;
        file.commitBlobMode = mode;

        if (staged)
          file.hasStagedChanges = YES;
        else
          file.hasUnstagedChanges = YES;
        if ([[fileStatus objectAtIndex:4] isEqualToString:@"D"])
          file.status = PBChangedFileStatusDeleted;
      } else {
        // Untracked file, set status to NEW, only unstaged changes
        file.hasStagedChanges = NO;
        file.hasUnstagedChanges = YES;
        file.status = PBChangedFileStatusNew;
      }

      // We handled this file, remove it from the dictionary
      [dictionary removeObjectForKey:file.path];
    } else {
      // Object not found in the dictionary, so let's reset its appropriate
      // change (stage or untracked) if necessary.

      // Staged dictionary, so file does not have staged changes
      if (staged)
        file.hasStagedChanges = NO;
      // Tracked file does not have unstaged changes, file is not new,
      // so we can set it to No. (If it would be new, it would not
      // be in this dictionary, but in the "other dictionary").
      else if (tracked && file.status != PBChangedFileStatusNew)
        file.hasUnstagedChanges = NO;
      // Unstaged, untracked dictionary ("Other" files), and file
      // is indicated as new (which would be untracked), so let's
      // remove it
      else if (!tracked && file.status == PBChangedFileStatusNew)
        file.hasUnstagedChanges = NO;
    }
  }

  // Do new files only if necessary
  if (![[dictionary allKeys] count])
    return;

  // All entries left in the dictionary haven't been accounted for
  // above, so we need to add them to the "files" array
  [self willChangeValueForKey:@"indexChanges"];
  for (NSString *path in [dictionary allKeys]) {
    NSArray *fileStatus = [dictionary objectForKey:path];

    PBChangedFile *file = [[PBChangedFile alloc] initWithPath:path];
    if ([[fileStatus objectAtIndex:4] isEqualToString:@"D"])
      file.status = PBChangedFileStatusDeleted;
    else if ([[fileStatus objectAtIndex:0] isEqualToString:@":000000"])
      file.status = PBChangedFileStatusNew;
    else
      file.status = PBChangedFileStatusModified;

    if (tracked) {
      file.commitBlobMode = [[fileStatus objectAtIndex:0] substringFromIndex:1];
      file.commitBlobSHA = [fileStatus objectAtIndex:2];
    }

    file.hasStagedChanges = staged;
    file.hasUnstagedChanges = !staged;

    [files addObject:file];
  }
  [self didChangeValueForKey:@"indexChanges"];
}

#pragma mark Utility methods

- (NSMutableDictionary *)dictionaryForLines:(NSArray *)lines {
  NSMutableDictionary *dictionary =
      [NSMutableDictionary dictionaryWithCapacity:[lines count] / 2];

  // Fill the dictionary with the new information. These lines are in the form
  // of: :00000 :0644 OTHER INDEX INFORMATION Filename

  NSAssert1([lines count] % 2 == 0,
            @"Lines must have an even number of lines: %@", lines);

  NSEnumerator *enumerator = [lines objectEnumerator];
  NSString *fileStatus;
  while (fileStatus = [enumerator nextObject]) {
    NSString *fileName = [enumerator nextObject];
    [dictionary setObject:[fileStatus componentsSeparatedByString:@" "]
                   forKey:fileName];
  }

  return dictionary;
}

@end
