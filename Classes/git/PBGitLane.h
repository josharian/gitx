//
//  PBGitLane.h
//  GitX
//
//  Created by Pieter de Bie on 27-08-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include <string>

class PBGitLane {
	std::string d_sha;
	int d_index;

public:

	PBGitLane(NSString *sha)
	{
		d_sha = [sha UTF8String];
	}

	PBGitLane(int index, NSString *sha)
	: d_index(index)
	{
		d_sha = [sha UTF8String];
	}
	
	bool isCommit(NSString *sha) const
	{
		return d_sha == [sha UTF8String];
	}
	
	void setSha(NSString *sha);
	
	NSString *sha() const
	{
		return [NSString stringWithUTF8String:d_sha.c_str()];
	}
	
	int index() const;
};