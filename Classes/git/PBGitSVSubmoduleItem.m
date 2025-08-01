//
//  PBGitSVSubmoduleItem.m
//  GitX
//
//  Created by Seth Raphael on 9/14/12.
//
//

#import "PBGitSVSubmoduleItem.h"

// REPLACE WITH GIT EXEC - Simple submodule data structure implementation
@implementation PBSubmoduleInfo
@end

@implementation PBGitSVSubmoduleItem

+ (id) itemWithSubmodule:(PBSubmoduleInfo*)submodule
{
    PBGitSVSubmoduleItem* item = [[self alloc] init];
	item.submodule = submodule;
    return item;
}

- (NSString *)title
{
	return self.submodule.name;
}

- (NSURL *)path
{
	NSURL *parentURL = self.submodule.parentRepositoryURL;
	NSURL *result = [parentURL URLByAppendingPathComponent:self.submodule.path];
	return result;
}
@end
