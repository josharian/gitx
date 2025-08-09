//
//  PBCommitID.h
//  GitX
//
//  Lightweight replacement for GTOID
//

#import <Foundation/Foundation.h>

@interface PBCommitID : NSObject <NSCopying> {
    NSString *_sha;
}

@property (readonly) NSString *sha;
@property (readonly) NSString *SHA;

+ (instancetype)commitIDWithSHA:(NSString *)sha;
- (BOOL)isEqual:(id)object;
- (NSUInteger)hash;

@end

@interface PBCommitID (JavaScript)
@end