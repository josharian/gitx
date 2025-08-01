//
//  PBGitSVSubmoduleItem.m
//  GitX
//
//  Created by Seth Raphael on 9/14/12.
//
//

#import "PBGitSVSubmoduleItem.h"

@implementation PBSubmoduleInfo

+ (NSArray<PBSubmoduleInfo *> *)submodulesForRepositoryURL:(NSURL *)repositoryURL {
    NSMutableArray *submodules = [NSMutableArray array];
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/git";
    task.arguments = @[@"config", @"--file", @".gitmodules", @"--get-regexp", @"^submodule\\..*\\.path$"];
    task.currentDirectoryPath = [repositoryURL path];
    
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    
    [task launch];
    [task waitUntilExit];
    
    if (task.terminationStatus == 0) {
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        
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
