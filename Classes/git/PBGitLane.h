//
//  PBGitLane.h
//  GitX
//
//  Created by Pieter de Bie on 27-08-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PBGitLane : NSObject

@property (nonatomic, copy, nullable) NSString *sha;
@property (nonatomic, assign, readonly) NSInteger index;

- (instancetype)initWithSHA:(nullable NSString *)sha;
- (instancetype)initWithIndex:(NSInteger)index sha:(nullable NSString *)sha NS_DESIGNATED_INITIALIZER;
- (BOOL)isCommit:(NSString *)sha;

@end

NS_ASSUME_NONNULL_END
