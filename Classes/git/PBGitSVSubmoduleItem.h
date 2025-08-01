//
//  PBGitSVSubmoduleItem.h
//  GitX
//
//  Created by Seth Raphael on 9/14/12.
//
//

#import <Foundation/Foundation.h>
#import "PBSourceViewItem.h"

@interface PBSubmoduleInfo : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *path;
@property (nonatomic, strong) NSURL *parentRepositoryURL;

+ (NSArray<PBSubmoduleInfo *> *)submodulesForRepositoryURL:(NSURL *)repositoryURL;
@end

@interface PBGitSVSubmoduleItem : PBSourceViewItem
+ (id) itemWithSubmodule:(PBSubmoduleInfo*)submodule;
@property (nonatomic, strong) PBSubmoduleInfo* submodule;
@property (nonatomic, readonly) NSURL *path;
@end
