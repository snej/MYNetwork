//
//  MYBonjourBrowser.m
//  MYNetwork
//
//  Created by Jens Alfke on 1/22/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import "MYBonjourBrowser.h"
#import "MYBonjourService.h"
#import "Test.h"
#import "Logging.h"


@interface MYBonjourBrowser ()
@property BOOL browsing;
@property (retain) NSError* error;
@end


@implementation MYBonjourBrowser


- (id) initWithServiceType: (NSString*)serviceType
{
    Assert(serviceType);
    self = [super init];
    if (self != nil) {
        _serviceType = [serviceType copy];
        _browser = [[NSNetServiceBrowser alloc] init];
        _browser.delegate = self;
        _services = [[NSMutableSet alloc] init];
        _addServices = [[NSMutableSet alloc] init];
        _rmvServices = [[NSMutableSet alloc] init];
        _serviceClass = [MYBonjourService class];
    }
    return self;
}


- (void) dealloc
{
    LogTo(Bonjour,@"DEALLOC BonjourBrowser");
    [_browser stop];
    _browser.delegate = nil;
    [_browser release];
    [_serviceType release];
    [_error release];
    [_services release];
    [_addServices release];
    [_rmvServices release];
    [super dealloc];
}


@synthesize browsing=_browsing, error=_error, services=_services, serviceClass=_serviceClass;


- (void) start
{
    [_browser searchForServicesOfType: _serviceType inDomain: @"local."];
}

- (void) stop
{
    [_browser stop];
}


- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)netServiceBrowser
{
    LogTo(Bonjour,@"%@ started browsing",self);
    self.browsing = YES;
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)netServiceBrowser
{
    LogTo(Bonjour,@"%@ stopped browsing",self);
    self.browsing = NO;
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser 
             didNotSearch:(NSDictionary *)errorDict
{
    NSString *domain = [errorDict objectForKey: NSNetServicesErrorDomain];
    int err = [[errorDict objectForKey: NSNetServicesErrorCode] intValue];
    self.error = [NSError errorWithDomain: domain code: err userInfo: nil];
    LogTo(Bonjour,@"%@ got error: ",self,self.error);
    self.browsing = NO;
}


- (void) _updateServiceList
{
    if( _rmvServices.count ) {
        [self willChangeValueForKey: @"services" 
                    withSetMutation: NSKeyValueMinusSetMutation
                       usingObjects: _rmvServices];
        [_services minusSet: _rmvServices];
        [self didChangeValueForKey: @"services" 
                   withSetMutation: NSKeyValueMinusSetMutation
                      usingObjects: _rmvServices];
        [_rmvServices makeObjectsPerformSelector: @selector(removed)];
        [_rmvServices removeAllObjects];
    }
    if( _addServices.count ) {
        [_addServices makeObjectsPerformSelector: @selector(added)];
        [self willChangeValueForKey: @"services" 
                    withSetMutation: NSKeyValueUnionSetMutation
                       usingObjects: _addServices];
        [_services unionSet: _addServices];
        [self didChangeValueForKey: @"services" 
                   withSetMutation: NSKeyValueUnionSetMutation
                      usingObjects: _addServices];
        [_addServices removeAllObjects];
    }
}


- (void) _handleService: (NSNetService*)netService 
                  addTo: (NSMutableSet*)addTo
             removeFrom: (NSMutableSet*)removeFrom
             moreComing: (BOOL)moreComing
{
    // Wrap the NSNetService in a BonjourService, using an existing instance if possible:
    MYBonjourService *service = [[_serviceClass alloc] initWithNetService: netService];
    MYBonjourService *existingService = [_services member: service];
    if( existingService ) {
        [service release];
        service = [existingService retain];
    }
    
    if( [removeFrom containsObject: service] )
        [removeFrom removeObject: service];
    else
        [addTo addObject: service];
    [service release];
    if( ! moreComing )
        [self _updateServiceList];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser 
           didFindService:(NSNetService *)netService
               moreComing:(BOOL)moreComing 
{
    //LogTo(Bonjour,@"Add service %@",netService);
    [self _handleService: netService addTo: _addServices removeFrom: _rmvServices moreComing: moreComing];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser 
         didRemoveService:(NSNetService *)netService 
               moreComing:(BOOL)moreComing 
{
    //LogTo(Bonjour,@"Remove service %@",netService);
    [self _handleService: netService addTo: _rmvServices removeFrom: _addServices moreComing: moreComing];
}


@end



#pragma mark -
#pragma mark TESTING:

@interface BonjourTester : NSObject
{
    MYBonjourBrowser *_browser;
}
@end

@implementation BonjourTester

- (id) init
{
    self = [super init];
    if (self != nil) {
        _browser = [[MYBonjourBrowser alloc] initWithServiceType: @"_http._tcp"];
        [_browser addObserver: self forKeyPath: @"services" options: NSKeyValueObservingOptionNew context: NULL];
        [_browser addObserver: self forKeyPath: @"browsing" options: NSKeyValueObservingOptionNew context: NULL];
        [_browser start];
    }
    return self;
}

- (void) dealloc
{
    [_browser stop];
    [_browser removeObserver: self forKeyPath: @"services"];
    [_browser removeObserver: self forKeyPath: @"browsing"];
    [_browser release];
    [super dealloc];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    LogTo(Bonjour,@"Observed change in %@: %@",keyPath,change);
    if( $equal(keyPath,@"services") ) {
        if( [[change objectForKey: NSKeyValueChangeKindKey] intValue]==NSKeyValueChangeInsertion ) {
            NSSet *newServices = [change objectForKey: NSKeyValueChangeNewKey];
            for( MYBonjourService *service in newServices ) {
                LogTo(Bonjour,@"    --> %@ : TXT=%@", service,service.txtRecord);
            }
        }
    }
}

@end

TestCase(Bonjour) {
    [NSRunLoop currentRunLoop]; // create runloop
    BonjourTester *tester = [[BonjourTester alloc] init];
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 15]];
    [tester release];
}



/*
 Copyright (c) 2008-2009, Jens Alfke <jens@mooseyard.com>. All rights reserved.
 
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
