//
//  BLIPDispatcher.h
//  MYNetwork
//
//  Created by Jens Alfke on 5/15/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>
@class MYTarget, BLIPMessage;


@interface BLIPDispatcher : NSObject 
{
    NSMutableArray *_predicates, *_targets;
    BLIPDispatcher *_parent;
}

@property (retain) BLIPDispatcher *parent;

- (void) addTarget: (MYTarget*)target forPredicate: (NSPredicate*)predicate;
- (void) removeTarget: (MYTarget*)target;

- (void) addTarget: (MYTarget*)target forValueOfProperty: (NSString*)value forKey: (NSString*)key;

- (BOOL) dispatchMessage: (BLIPMessage*)message;

@end
