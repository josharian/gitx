//
//  PBGitGrapher.m
//  GitX
//
//  Created by Pieter de Bie on 17-06-08.
//  Converted to Objective-C from mixed Objective-C++.
//

#import "PBGraphCellInfo.h"
#import "PBGitGrapher.h"
#import "PBGitCommit.h"
#import "PBGitLane.h"
#import "PBGitGraphLine.h"
#import <limits.h>

static inline int PBGitClampedInt(NSInteger value)
{
    if (value > INT_MAX) {
        return INT_MAX;
    }

    if (value < INT_MIN) {
        return INT_MIN;
    }

    return (int)value;
}

static inline void PBGitAddLine(struct PBGitGraphLine *lines,
                                int *currentIndex,
                                BOOL upper,
                                NSInteger from,
                                NSInteger to,
                                NSInteger laneIndex)
{
    struct PBGitGraphLine line = {
        .upper = upper ? 1 : 0,
        .from = PBGitClampedInt(from),
        .to = PBGitClampedInt(to),
        .colorIndex = PBGitClampedInt(laneIndex)
    };

    lines[(*currentIndex)++] = line;
}

static NSString *PBGitParentSHA(id candidate)
{
    if ([candidate isKindOfClass:[NSString class]]) {
        return candidate;
    }

    return nil;
}

@interface PBGitGrapher ()

@property (nonatomic, strong) PBGraphCellInfo *previous;
@property (nonatomic, strong) NSMutableArray *lanes; // Holds PBGitLane instances or NSNull placeholders.
@property (nonatomic, assign) NSInteger laneIndex;

@end

@implementation PBGitGrapher

- (instancetype)initWithRepository:(__unused PBGitRepository *)repo
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _lanes = [NSMutableArray array];
    _laneIndex = 0;

    return self;
}

- (void)decorateCommit:(PBGitCommit *)commit
{
    NSMutableArray *previousLanes = self.lanes;
    NSMutableArray *currentLanes = [NSMutableArray array];

    NSArray *parents = [commit parents];
    NSInteger parentCount = (NSInteger)parents.count;

    NSInteger maxLines = ((NSInteger)previousLanes.count + parentCount + 2) * 2;
    struct PBGitGraphLine *lines = (struct PBGitGraphLine *)malloc(sizeof(struct PBGitGraphLine) * maxLines);
    int currentLine = 0;

    NSInteger newPosition = -1;
    PBGitLane *currentLane = nil;
    BOOL didProcessFirstParent = NO;

    NSString *commitSHA = [commit sha];

    NSInteger columnIndex = 0;
    for (id laneCandidate in previousLanes) {
        columnIndex++;

        if (laneCandidate == [NSNull null]) {
            continue;
        }

        PBGitLane *lane = (PBGitLane *)laneCandidate;
        if ([lane isCommit:commitSHA]) {
            if (!didProcessFirstParent) {
                didProcessFirstParent = YES;
                [currentLanes addObject:lane];
                currentLane = lane;
                newPosition = (NSInteger)currentLanes.count;

                PBGitAddLine(lines, &currentLine, YES, columnIndex, newPosition, lane.index);
                if (parentCount > 0) {
                    PBGitAddLine(lines, &currentLine, NO, newPosition, newPosition, lane.index);
                }
            } else {
                PBGitAddLine(lines, &currentLine, YES, columnIndex, newPosition, lane.index);
            }
        } else {
            [currentLanes addObject:lane];
            NSInteger lanePosition = (NSInteger)currentLanes.count;
            PBGitAddLine(lines, &currentLine, YES, columnIndex, lanePosition, lane.index);
            PBGitAddLine(lines, &currentLine, NO, lanePosition, lanePosition, lane.index);
        }
    }

    if (!didProcessFirstParent && parentCount > 0) {
        NSString *parentSHA = PBGitParentSHA(parents.firstObject);
        if (!parentSHA) {
            free(lines);
            return;
        }

        PBGitLane *newLane = [[PBGitLane alloc] initWithIndex:self.laneIndex++ sha:parentSHA];
        [currentLanes addObject:newLane];
        newPosition = (NSInteger)currentLanes.count;
        PBGitAddLine(lines, &currentLine, NO, newPosition, newPosition, newLane.index);
    }

    BOOL addedParent = NO;
    if (parentCount > 1) {
        for (NSInteger parentIndex = 1; parentIndex < parentCount; parentIndex++) {
            NSString *parentSHA = PBGitParentSHA(parents[parentIndex]);
            if (!parentSHA) {
                continue;
            }

            NSInteger lanePosition = 0;
            BOOL alreadyDisplayed = NO;

            for (id laneCandidate in currentLanes) {
                lanePosition++;

                if (laneCandidate == [NSNull null]) {
                    continue;
                }

                PBGitLane *lane = (PBGitLane *)laneCandidate;
                if ([lane isCommit:parentSHA]) {
                    PBGitAddLine(lines, &currentLine, NO, lanePosition, newPosition, lane.index);
                    alreadyDisplayed = YES;
                    break;
                }
            }

            if (alreadyDisplayed) {
                continue;
            }

            addedParent = YES;
            PBGitLane *newLane = [[PBGitLane alloc] initWithIndex:self.laneIndex++ sha:parentSHA];
            [currentLanes addObject:newLane];
            NSInteger lanePositionForNewLane = (NSInteger)currentLanes.count;
            PBGitAddLine(lines, &currentLine, NO, lanePositionForNewLane, newPosition, newLane.index);
        }
    }

    if (!commit.lineInfo) {
        self.previous = [[PBGraphCellInfo alloc] initWithPosition:PBGitClampedInt(newPosition) andLines:lines];
    } else {
        self.previous = commit.lineInfo;
        self.previous.position = PBGitClampedInt(newPosition);
        self.previous.lines = lines;
    }

    if (currentLine > maxLines) {
        NSLog(@"Number of lines: %d vs allocated: %ld", currentLine, (long)maxLines);
    }

    self.previous.nLines = currentLine;
    self.previous.sign = commit.sign;
    self.previous.numColumns = addedParent ? (int)currentLanes.count - 1 : (int)currentLanes.count;

    if (currentLane) {
        NSString *firstParent = PBGitParentSHA(parents.firstObject);
        if (firstParent.length > 0) {
            currentLane.sha = firstParent;
        } else if (parentCount == 0) {
            NSUInteger slot = [currentLanes indexOfObjectIdenticalTo:currentLane];
            if (slot != NSNotFound) {
                currentLanes[slot] = [NSNull null];
            }
        }
    }

    self.lanes = currentLanes;
    commit.lineInfo = self.previous;
}

@end
