//
//  PBChangedFile.h
//  GitX
//
//  Created by Pieter de Bie on 22-09-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PBChangedFileStatus) {
    PBChangedFileStatusNew,
    PBChangedFileStatusModified,
    PBChangedFileStatusDeleted
};

@interface PBChangedFile : NSObject {
	NSString *path;
	BOOL hasStagedChanges;
	BOOL hasUnstagedChanges;

	// Index and HEAD stuff, to be used to revert changes
	NSString * _Nullable commitBlobSHA;
	NSString * _Nullable commitBlobMode;

	PBChangedFileStatus status;
}


@property (copy) NSString *path;
@property (copy, nullable) NSString *commitBlobSHA;
@property (copy, nullable) NSString *commitBlobMode;
@property (assign) PBChangedFileStatus status;
@property (assign) BOOL hasStagedChanges;
@property (assign) BOOL hasUnstagedChanges;

- (NSImage *)icon;
- (NSString *)indexInfo;

- (instancetype)initWithPath:(NSString *)path;
@end

NS_ASSUME_NONNULL_END
