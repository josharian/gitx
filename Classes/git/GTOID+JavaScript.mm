//
//  GTOID+JavaScript.m
//  GitX
//
//  Created by Sven Weidauer on 18.05.14.
//
//

#import "GTOID+JavaScript.h"

@implementation GTOID

@synthesize sha = _sha;

+ (instancetype)oidWithSHA:(NSString *)sha {
	GTOID *oid = [[GTOID alloc] init];
	oid->_sha = [sha copy];
	
	// Allocate git_oid struct and parse SHA-1 string into binary format
	oid->_git_oid = (git_oid*)malloc(sizeof(git_oid));
	
	// Convert hex string to binary SHA-1 (40 hex chars -> 20 bytes)
	if ([sha length] >= 40) {
		const char *hexString = [sha UTF8String];
		for (int i = 0; i < 20; i++) {
			sscanf(hexString + (i * 2), "%2hhx", &oid->_git_oid->id[i]);
		}
	} else {
		// Invalid SHA, zero out the structure
		memset(oid->_git_oid, 0, sizeof(git_oid));
	}
	
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
