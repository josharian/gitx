//
//  PBCommitData.h
//  GitX
//
//  Swift-backed lightweight commit model accessible from Objective-C.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PBCommitData : NSObject

@property (nonatomic, strong, nullable) NSString *sha;
@property (nonatomic, strong, nullable) NSString *shortSHA;
@property (nonatomic, strong, nullable) NSString *message;
@property (nonatomic, strong, nullable) NSString *messageSummary;
@property (nonatomic, strong, nullable) NSDate *commitDate;
@property (nonatomic, strong, nullable) NSString *authorName;
@property (nonatomic, strong, nullable) NSString *committerName;
@property (nonatomic, strong, nullable) NSArray<NSString *> *parentSHAs;

- (instancetype)initWithSha:(nullable NSString *)sha
                    shortSHA:(nullable NSString *)shortSHA
                      message:(nullable NSString *)message
               messageSummary:(nullable NSString *)messageSummary
                   commitDate:(nullable NSDate *)commitDate
                  authorName:(nullable NSString *)authorName
               committerName:(nullable NSString *)committerName
                  parentSHAs:(nullable NSArray<NSString *> *)parentSHAs NS_DESIGNATED_INITIALIZER;

- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
