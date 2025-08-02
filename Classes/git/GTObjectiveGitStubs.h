//
//  GTObjectiveGitStubs.h
//  GitX
//
//  Stubs to replace ObjectiveGit dependencies
//

#import <Foundation/Foundation.h>

// Forward declarations
@class GTOID;
@class GTRepository;

// GTObjectType constants
typedef enum {
    GTObjectTypeCommit = 1
} GTObjectType;

// GTEnumeratorOptions constants
typedef NSUInteger GTEnumeratorOptions;
static const GTEnumeratorOptions GTEnumeratorOptionsNone = 0;
static const GTEnumeratorOptions GTEnumeratorOptionsTimeSort = 1;
static const GTEnumeratorOptions GTEnumeratorOptionsTopologicalSort = 2;

@interface GTSignature : NSObject
@property (nonatomic, strong) NSString *name;
@end

@interface GTObject : NSObject
@property (nonatomic, strong) NSString *SHA;
- (id)objectByPeelingToType:(GTObjectType)type error:(NSError **)error;
@end

@interface GTCommit : GTObject
@property (nonatomic, strong) NSDate *commitDate;
@property (nonatomic, strong) NSString *messageSummary;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, strong) GTSignature *author;
@property (nonatomic, strong) GTSignature *committer;
@property (nonatomic, strong) NSArray *parents;
@property (nonatomic, strong) GTOID *OID;
@property (nonatomic, strong) NSString *shortSHA;
@end

@interface GTBranch : NSObject
@property (nonatomic, strong) NSString *SHA;
@end

@interface GTTag : NSObject
- (GTCommit *)objectByPeelingTagError:(NSError **)error;
@end

@interface GTRepository : NSObject
@end

@interface GTEnumerator : NSObject
@property (nonatomic, strong) id repository;
@property (nonatomic, strong) NSMutableArray *commitQueue;
@property (nonatomic, strong) NSMutableArray *revListArgs;
@property (nonatomic, assign) GTEnumeratorOptions options;
@property (nonatomic, assign) BOOL hasPopulated;
- (id)initWithRepository:(id)repo error:(NSError **)error;
- (void)resetWithOptions:(GTEnumeratorOptions)options;
- (void)pushGlob:(NSString *)glob error:(NSError **)error;
- (void)pushSHA:(NSString *)sha error:(NSError **)error;
- (GTCommit *)nextObjectWithSuccess:(BOOL *)success error:(NSError **)error;
- (void)populateQueueWithRevList;
- (void)parseRevListOutput:(NSString *)output;
@end

