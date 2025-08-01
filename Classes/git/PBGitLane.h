//
//  PBGitLane.h
//  GitX
//
//  Created by Pieter de Bie on 27-08-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// REPLACE WITH GIT EXEC - Simple git_oid stub to replace libgit2 dependency
typedef struct {
    unsigned char id[20]; // SHA-1 is 20 bytes
} git_oid;

// REPLACE WITH GIT EXEC - Simple stub functions for git_oid
static inline void git_oid_cpy(git_oid *out, const git_oid *src) {
    memcpy(out, src, sizeof(git_oid));
}

static inline int git_oid_cmp(const git_oid *a, const git_oid *b) {
    return memcmp(a, b, sizeof(git_oid));
}

class PBGitLane {
	git_oid d_sha;
	int d_index;

public:

	PBGitLane(const git_oid *sha)
	{
		d_sha = *sha;
	}

	PBGitLane(int index, const git_oid *sha)
	: d_index(index)
	{
		git_oid_cpy(&d_sha, sha);
	}
	
	bool isCommit(const git_oid *sha) const
	{
		return !git_oid_cmp(&d_sha, sha);
	}
	
	void setSha(const git_oid *sha);
	
	git_oid const *sha() const
	{
		return &d_sha;
	}
	
	int index() const;
};