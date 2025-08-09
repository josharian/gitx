//
//  PBCommitData.h
//  GitX
//
//  Lightweight replacement for GTCommit
//

#import <Foundation/Foundation.h>

@interface PBCommitData : NSObject

@property (nonatomic, strong) NSString *sha;
@property (nonatomic, strong) NSString *shortSHA;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, strong) NSString *messageSummary;
@property (nonatomic, strong) NSDate *commitDate;
@property (nonatomic, strong) NSString *authorName;
@property (nonatomic, strong) NSString *committerName;
@property (nonatomic, strong) NSArray<NSString *> *parentSHAs;

@end