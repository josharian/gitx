//
//  GTObjectiveGitStubs.h
//  GitX
//
//  REPLACE WITH GIT EXEC - Temporary stubs to replace ObjectiveGit dependencies
//

#import <Foundation/Foundation.h>

// Forward declarations
@class GTOID;

// GTObjectType constants
typedef enum {
    GTObjectTypeCommit = 1
} GTObjectType;

@interface GTSignature : NSObject
@property (nonatomic, strong) NSString *name;
@end

@interface GTCommit : NSObject
@property (nonatomic, strong) NSDate *commitDate;
@property (nonatomic, strong) NSString *messageSummary;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, strong) GTSignature *author;
@property (nonatomic, strong) GTSignature *committer;
@property (nonatomic, strong) NSArray *parents;
@property (nonatomic, strong) GTOID *OID;
@property (nonatomic, strong) NSString *SHA;
@property (nonatomic, strong) NSString *shortSHA;
@end

@interface GTObject : NSObject
@property (nonatomic, strong) NSString *SHA;
- (id)objectByPeelingToType:(GTObjectType)type error:(NSError **)error;
@end

@interface GTBranch : NSObject
@property (nonatomic, strong) NSString *SHA;
@end

@interface GTTag : NSObject
- (GTCommit *)objectByPeelingTagError:(NSError **)error;
@end

@interface GTEnumerator : NSObject
@property (nonatomic, strong) id repository; // GTRepository stub
- (id)initWithRepository:(id)repo error:(NSError **)error;
- (void)resetWithOptions:(NSUInteger)options;
- (void)pushGlob:(NSString *)glob error:(NSError **)error;
- (void)pushSHA:(NSString *)sha error:(NSError **)error;
- (GTCommit *)nextObjectWithSuccess:(BOOL *)success error:(NSError **)error;
@end

// GTEnumerator option constants
#define GTEnumeratorOptionsTimeSort 0
#define GTEnumeratorOptionsTopologicalSort 1