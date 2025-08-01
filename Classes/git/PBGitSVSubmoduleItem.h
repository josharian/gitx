//
//  PBGitSVSubmoduleItem.h
//  GitX
//
//  Created by Seth Raphael on 9/14/12.
//
//

#import <Foundation/Foundation.h>
#import "PBSourceViewItem.h"

// REPLACE WITH GIT EXEC - Simple submodule data structure instead of GTSubmodule
@interface PBSubmoduleInfo : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *path;
@property (nonatomic, strong) NSURL *parentRepositoryURL;
@end

@interface PBGitSVSubmoduleItem : PBSourceViewItem
+ (id) itemWithSubmodule:(PBSubmoduleInfo*)submodule;
@property (nonatomic, strong) PBSubmoduleInfo* submodule;
@property (nonatomic, readonly) NSURL *path;
@end
