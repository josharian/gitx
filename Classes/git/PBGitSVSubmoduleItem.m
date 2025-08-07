//
//  PBGitSVSubmoduleItem.m
//  GitX
//
//  Created by Seth Raphael on 9/14/12.
//
//

#import "PBGitSVSubmoduleItem.h"
#import "PBGitBinary.h"
#import "PBEasyPipe.h"

@implementation PBSubmoduleInfo

+ (NSArray<PBSubmoduleInfo *> *)submodulesForRepositoryURL:(NSURL *)repositoryURL {
    NSMutableArray *submodules = [NSMutableArray array];
    
    NSString *gitPath = [PBGitBinary path];
    if (!gitPath) {
        gitPath = @"/usr/bin/git"; // Fallback
    }
    
    int exitCode = 0;
    NSString *output = [PBEasyPipe outputForCommand:gitPath
                                          withArgs:@[@"config", @"--file", @".gitmodules", @"--get-regexp", @"^submodule\\..*\\.path$"]
                                             inDir:[repositoryURL path]
                                          retValue:&exitCode];
    
    if (exitCode == 0 && output) {
        
        NSArray *lines = [output componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            if ([line length] > 0) {
                NSRange pathRange = [line rangeOfString:@"submodule."];
                NSRange dotPathRange = [line rangeOfString:@".path "];
                
                if (pathRange.location != NSNotFound && dotPathRange.location != NSNotFound) {
                    NSString *name = [line substringWithRange:NSMakeRange(pathRange.location + pathRange.length, 
                                                                         dotPathRange.location - (pathRange.location + pathRange.length))];
                    NSString *path = [[line substringFromIndex:dotPathRange.location + dotPathRange.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    
                    PBSubmoduleInfo *info = [[PBSubmoduleInfo alloc] init];
                    info.name = name;
                    info.path = path;
                    info.parentRepositoryURL = repositoryURL;
                    [submodules addObject:info];
                }
            }
        }
    }
    
    return [submodules copy];
}

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
