//
//  PBGitLane.m
//  GitX
//
//  Created by Pieter de Bie on 27-08-08.
//  Updated to Objective-C implementation.
//

#import "PBGitLane.h"

@interface PBGitLane ()
@property (nonatomic, assign, readwrite) NSInteger index;
@end

@implementation PBGitLane

- (instancetype)initWithSHA:(NSString *)sha
{
    return [self initWithIndex:NSNotFound sha:sha];
}

- (instancetype)initWithIndex:(NSInteger)index sha:(NSString *)sha
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _index = index;
    _sha = [sha copy];

    return self;
}

- (BOOL)isCommit:(NSString *)sha
{
    if (!sha.length || !self.sha.length) {
        return NO;
    }

    return [self.sha isEqualToString:sha];
}

@end
