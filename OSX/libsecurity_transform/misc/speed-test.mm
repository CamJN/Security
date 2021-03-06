/*
 * Copyright (c) 2010 Apple Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */


#import "speed-test.h"
#include "SecTransform.h"
#include "SecExternalSourceTransform.h"
#include "SecNullTransform.h"
#include <security_utilities/simulatecrash_assert.h>

@implementation speed_test

@end

UInt8 zeros[1024];

typedef void (^push_block_t)(CFDataRef d);

void timed_test(NSString *name, float seconds, SecTransformRef tr, push_block_t push) {
	__block int num_out = 0;
	__block int num_in = 0;
	__block int timeout_out = -1;
	__block int timeout_in = -1;
	volatile __block bool done;
	static CFDataRef z = CFDataCreateWithBytesNoCopy(NULL, zeros, sizeof(zeros), NULL);
	
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(seconds * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
		done = true;
		timeout_out = num_out;
		timeout_in = num_in;
	});
	
	dispatch_group_t dg = dispatch_group_create();
	dispatch_group_enter(dg);
	
	dispatch_queue_t q = dispatch_queue_create("counter", NULL);
	
	SecTransformExecuteAsync(tr, q, ^(CFTypeRef message, CFErrorRef error, Boolean isFinal) {
		if (message) {
			num_out++;
		}
		if (error) {
			NSLog(@"Error %@ while running %@", error, name);
		}
		if (isFinal) {
			dispatch_group_leave(dg);
		}
	});
	
	while (!done) {
		push(z);
		num_in++;
	}
	push(NULL);
	dispatch_group_wait(dg, DISPATCH_TIME_FOREVER);
	NSString *m = [NSString stringWithFormat:@"%@ %d in, %d out times in %f seconds, %d stragglers\n", name, timeout_in, timeout_out, seconds, num_out - timeout_out];
	[m writeToFile:@"/dev/stdout" atomically:NO encoding:NSUTF8StringEncoding error:NULL];
}

int main(int argc, char *argv[]) {
	NSAutoreleasePool *ap = [[NSAutoreleasePool alloc] init];
	float seconds = 5.0;
	
	{
		SecTransformRef x = SecExternalSourceTransformCreate(NULL);
		//SecTransformRef t = SecEncodeTransformCreate(kSecBase64Encoding, NULL);
		SecTransformRef t = SecNullTransformCreate();
		SecTransformRef g = SecTransformCreateGroupTransform();
		assert(x && t && g);
		SecTransformConnectTransforms(x, kSecTransformOutputAttributeName, t, kSecTransformInputAttributeName, g, NULL);
		
		timed_test(@"external source", seconds, t, ^(CFDataRef d){
			SecExternalSourceSetValue(x, d, NULL);
		});
		
	}
	
	// This second test has issues with the stock transform framwork -- it don't think the graph is valid (missing input)
	{
		//SecTransformRef t = SecEncodeTransformCreate(kSecBase64Encoding, NULL);
		SecTransformRef t = SecNullTransformCreate();
		assert(t);
		
		timed_test(@"set INPUT", seconds, t, ^(CFDataRef d){
			SecTransformSetAttribute(t, kSecTransformInputAttributeName, d, NULL);
		});
	}
}
