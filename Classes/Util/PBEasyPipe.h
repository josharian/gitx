//
//  PBEasyPipe.h
//  GitX
//
//  Created by Pieter de Bie on 16-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PBEasyPipe : NSObject

+ (nullable NSTask *)taskForCommand:(NSString *)command
                            withArgs:(NSArray<NSString *> *)arguments
                               inDir:(nullable NSString *)directory;

+ (nullable NSFileHandle *)handleForCommand:(NSString *)command
                                    withArgs:(NSArray<NSString *> *)arguments;

+ (nullable NSFileHandle *)handleForCommand:(NSString *)command
                                    withArgs:(NSArray<NSString *> *)arguments
                                       inDir:(nullable NSString *)directory;

+ (nullable NSString *)outputForCommand:(NSString *)command
                                 withArgs:(NSArray<NSString *> *)arguments;

+ (nullable NSString *)outputForCommand:(NSString *)command
                                 withArgs:(NSArray<NSString *> *)arguments
                                    inDir:(nullable NSString *)directory;

+ (nullable NSString *)outputForCommand:(NSString *)command
                                 withArgs:(NSArray<NSString *> *)arguments
                                    inDir:(nullable NSString *)directory
                                  retValue:(nullable int *)returnCode;

+ (nullable NSString *)outputForCommand:(NSString *)command
                                 withArgs:(NSArray<NSString *> *)arguments
                                    inDir:(nullable NSString *)directory
                               inputString:(nullable NSString *)input
                                  retValue:(nullable int *)returnCode;

+ (nullable NSString *)outputForCommand:(NSString *)command
                                 withArgs:(NSArray<NSString *> *)arguments
                                    inDir:(nullable NSString *)directory
                 byExtendingEnvironment:(nullable NSDictionary<NSString *, NSString *> *)environment
                               inputString:(nullable NSString *)input
                                  retValue:(nullable int *)returnCode;

+ (nullable NSString *)gitOutputForArgs:(NSArray<NSString *> *)arguments
                                   inDir:(nullable NSString *)directory
                                   error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
