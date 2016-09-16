//
//  APNSIdentityChooser.h
//  Knuff
//
//  Created by Joel Ekström on 2016-09-16.
//  Copyright © 2016 Bowtie. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@interface APNSIdentityChooser : NSObject

@property (nonatomic, readonly) SecIdentityRef selectedIdentity;

- (void)displayWithWindow:(NSWindow *)window completion:(void(^)(SecIdentityRef selectedIdentity))completionBlock;

@end
