//
//  GTOID+JavaScript.m
//  GitX
//
//  Created by Sven Weidauer on 18.05.14.
//
//

#import "GTOID+JavaScript.h"

// REPLACE WITH GIT EXEC - Basic GTOID implementation
@implementation GTOID

@synthesize sha = _sha;

+ (instancetype)oidWithSHA:(NSString *)sha {
	GTOID *oid = [[GTOID alloc] init];
	oid->_sha = [sha copy];
	// Allocate and initialize git_oid struct with zeros for stub
	oid->_git_oid = (git_oid*)malloc(sizeof(git_oid));
	memset(oid->_git_oid, 0, sizeof(git_oid));
	return oid;
}

- (NSString *)SHA {
	return self.sha; // Alias for sha property
}

- (const git_oid *)git_oid {
	return _git_oid; // Return pointer to stub git_oid
}

- (void)dealloc {
	if (_git_oid) {
		free(_git_oid);
	}
}

- (BOOL)isEqual:(id)object {
	if ([object isKindOfClass:[GTOID class]]) {
		return [self.sha isEqualToString:((GTOID *)object).sha];
	} else if ([object isKindOfClass:[NSString class]]) {
		return [self.sha isEqualToString:(NSString *)object];
	}
	return NO;
}

- (NSUInteger)hash {
	return [self.sha hash];
}

@end

@implementation GTOID (JavaScript)

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector
{
	return NO;
}

+ (BOOL)isKeyExcludedFromWebScript:(const char *)name {
	return NO;
}

@end
