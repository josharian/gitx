//
//  PBEasyPipe.m
//  GitX
//
//  Created by Pieter de Bie on 16-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBEasyPipe.h"


@implementation PBEasyPipe

+ (NSFileHandle*) handleForCommand: (NSString*) cmd withArgs: (NSArray*) args
{
	return [self handleForCommand:cmd withArgs:args inDir:nil];
}

+ (NSTask *) taskForCommand:(NSString *)cmd withArgs:(NSArray *)args inDir:(NSString *)dir
{
	NSTask* task = [[NSTask alloc] init];
	[task setLaunchPath:cmd];
	[task setArguments:args];

    // Prepare ourselves a nicer environment
    NSMutableDictionary *env = [[[NSProcessInfo processInfo] environment] mutableCopy];
    [env removeObjectsForKeys:@[@"MallocStackLogging", @"MallocStackLoggingNoCompact", @"NSZombieEnabled"]];
    [task setEnvironment:env];

	if (dir)
		[task setCurrentDirectoryPath:dir];

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"Show Debug Messages"])
		NSLog(@"Starting command `%@ %@` in dir %@", cmd, [args componentsJoinedByString:@" "], dir);
#ifdef CLI
	NSLog(@"Starting command `%@ %@` in dir %@", cmd, [args componentsJoinedByString:@" "], dir);
#endif

	NSPipe* pipe = [NSPipe pipe];
	[task setStandardOutput:pipe];
	[task setStandardError:pipe];
	return task;
}

+ (NSFileHandle*) handleForCommand: (NSString*) cmd withArgs: (NSArray*) args inDir: (NSString*) dir
{
	NSTask *task = [self taskForCommand:cmd withArgs:args inDir:dir];
	NSFileHandle* handle = [[task standardOutput] fileHandleForReading];
	
	[task launch];
	return handle;
}



+ (NSString*) outputForCommand:(NSString *) cmd
					  withArgs:(NSArray *)  args
						 inDir:(NSString *) dir
				      retValue:(int *)      ret
{
	return [self outputForCommand:cmd withArgs:args inDir:dir byExtendingEnvironment:nil inputString:nil retValue:ret];
}	

+ (NSString*) outputForCommand:(NSString *) cmd
					  withArgs:(NSArray *)  args
						 inDir:(NSString *) dir
				   inputString:(NSString *) input
				      retValue:(int *)      ret
{
	return [self outputForCommand:cmd withArgs:args inDir:dir byExtendingEnvironment:nil inputString:input retValue:ret];
}

+ (NSString*) outputForCommand:(NSString *)    cmd
					  withArgs:(NSArray *)     args
						 inDir:(NSString *)    dir
		byExtendingEnvironment:(NSDictionary *)dict
				   inputString:(NSString *)    input
					  retValue:(int *)         ret
{
	NSTask *task = [self taskForCommand:cmd withArgs:args inDir:dir];

	if (dict) {
		NSMutableDictionary *env = [[[NSProcessInfo processInfo] environment] mutableCopy];
		[env addEntriesFromDictionary:dict];
		[task setEnvironment:env];
	}

	NSFileHandle* handle = [[task standardOutput] fileHandleForReading];

	if (input) {
		[task setStandardInput:[NSPipe pipe]];
		NSFileHandle *inHandle = [[task standardInput] fileHandleForWriting];
		[inHandle writeData:[input dataUsingEncoding:NSUTF8StringEncoding]];
		[inHandle closeFile];
	}
	
	[task launch];
	
	NSData* data = [handle readDataToEndOfFile];
	NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!string)
		string = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
	
	// Strip trailing newline
	if ([string hasSuffix:@"\n"])
		string = [string substringToIndex:[string length]-1];
	
	[task waitUntilExit];
	if (ret)
		*ret = [task terminationStatus];
	return string;
}	



+ (NSString*) outputForCommand: (NSString*) cmd withArgs: (NSArray*) args inDir: (NSString*) dir
{
	int ret;
	return [self outputForCommand:cmd withArgs:args inDir:dir retValue:&ret];
}

+ (NSString*) outputForCommand: (NSString*) cmd withArgs: (NSArray*) args
{
	return [self outputForCommand:cmd withArgs:args inDir:nil];
}

+ (NSString*) gitOutputForArgs:(NSArray *)args
                         inDir:(NSString *)dir
                         error:(NSError **)error
{
    NSString *gitPath = [[NSClassFromString(@"PBGitBinary") performSelector:@selector(path)] copy];
    if (!gitPath) {
        if (error) {
            *error = [NSError errorWithDomain:@"PBGitRepositoryErrorDomain" 
                                         code:1004 // PBGitErrorGitNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Git binary not found"}];
        }
        return nil;
    }
    
    int exitCode = 0;
    NSString *output = [self outputForCommand:gitPath 
                                     withArgs:args 
                                        inDir:dir 
                                     retValue:&exitCode];
    
    if (exitCode != 0 && error) {
        NSString *errorMessage = [NSString stringWithFormat:@"Git command failed with exit code %d", exitCode];
        *error = [NSError errorWithDomain:@"PBGitRepositoryErrorDomain" 
                                     code:1001 // PBGitErrorCommandFailed
                                 userInfo:@{NSLocalizedDescriptionKey: errorMessage,
                                           @"GitArgs": args ?: @[],
                                           @"ExitCode": @(exitCode)}];
    }
    
    return exitCode == 0 ? output : nil;
}

@end
