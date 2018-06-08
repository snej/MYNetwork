//
//  BLIPDispatcher.m
//  MYNetwork
//
//  Created by Jens Alfke on 5/15/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import "BLIPDispatcher.h"
#import "Target.h"
#import "BLIPRequest.h"
#import "BLIPProperties.h"
#import "Logging.h"
#import "Test.h"


@implementation BLIPDispatcher
{
    NSMutableArray *_predicates, *_targets;
    BLIPDispatcher *_parent;
}


- (id) init
{
    self = [super init];
    if (self != nil) {
        _targets = [[NSMutableArray alloc] init];
        _predicates = [[NSMutableArray alloc] init];
    }
    return self;
}



@synthesize parent=_parent;


- (void) addTarget: (MYTarget*)target forPredicate: (NSPredicate*)predicate
{
    [_targets addObject: target];
    [_predicates addObject: predicate];
}


- (void) removeTarget: (MYTarget*)target
{
    NSUInteger i = [_targets indexOfObject: target];
    if( i != NSNotFound ) {
        [_targets removeObjectAtIndex: i];
        [_predicates removeObjectAtIndex: i];
    }
}


- (void) addTarget: (MYTarget*)target forValueOfProperty: (NSString*)value forKey: (NSString*)key
{
    [self addTarget:target forPredicate:[NSComparisonPredicate predicateWithLeftExpression: [NSExpression expressionForKeyPath: key]
                                                                           rightExpression: [NSExpression expressionForConstantValue: value]
                                                                                  modifier: NSDirectPredicateModifier
                                                                                      type: NSEqualToPredicateOperatorType
                                                                                   options: 0]];
}


static BOOL testPredicate( id predicate, NSDictionary *properties ) {
    return [(NSPredicate*)predicate evaluateWithObject: properties];
}


- (BOOL) dispatchMessage: (BLIPMessage*)message
{
    NSDictionary *properties = message.properties.allProperties;
    NSUInteger n = _predicates.count;
    for( NSUInteger i=0; i<n; i++ ) {
        id p = _predicates[i];
        if( testPredicate(p, properties) ) {
            MYTarget *target = _targets[i];
            LogTo(BLIP,@"Dispatcher matched %@ -- calling %@",p,target);
            [target invokeWithSender: message];
            return YES;
        }
    }
    return [_parent dispatchMessage: message];
}


- (MYTarget*) asTarget;
{
    return $target(self,dispatchMessage:);
}


@end


/*
 Copyright (c) 2008, Jens Alfke <jens@mooseyard.com>. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted
 provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions
 and the following disclaimer in the documentation and/or other materials provided with the
 distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRI-
 BUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR 
  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF 
 THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
