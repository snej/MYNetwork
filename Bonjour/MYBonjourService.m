//
//  MYBonjourService.m
//  MYNetwork
//
//  Created by Jens Alfke on 1/22/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import "MYBonjourService.h"
#import "IPAddress.h"
#import "ConcurrentOperation.h"
#import "Test.h"
#import "Logging.h"


NSString* const kBonjourServiceResolvedAddressesNotification = @"BonjourServiceResolvedAddresses";


@interface MYBonjourService ()
@property (copy) NSSet* addresses;
@end

@interface MYBonjourResolveOperation ()
@property (assign) MYBonjourService *service;
@property (retain) NSSet *addresses;
@end



@implementation MYBonjourService


- (id) initWithNetService: (NSNetService*)netService
{
    self = [super init];
    if (self != nil) {
        _netService = [netService retain];
        _netService.delegate = self;
    }
    return self;
}

- (void) dealloc
{
    Log(@"DEALLOC %@",self);
    _netService.delegate = nil;
    [_netService release];
    [_txtRecord release];
    [_addresses release];
    [super dealloc];
}


- (NSString*) description
{
    return $sprintf(@"%@['%@'.%@%@]", self.class,self.name,_netService.type,_netService.domain);
}


- (NSComparisonResult) compare: (id)obj
{
    return [self.name caseInsensitiveCompare: [obj name]];
}


- (NSNetService*) netService        {return _netService;}
- (BOOL) isEqual: (id)obj           {return [obj isKindOfClass: [MYBonjourService class]] && [_netService isEqual: [obj netService]];}
- (NSUInteger) hash                 {return _netService.hash;}
- (NSString*) name                  {return _netService.name;}


- (void) added
{
    LogTo(Bonjour,@"Added %@",_netService);
}

- (void) removed
{
    LogTo(Bonjour,@"Removed %@",_netService);
    [_netService stopMonitoring];
    _netService.delegate = nil;
    
    if( _resolveOp ) {
        [_resolveOp cancel];
        [_resolveOp release];
        _resolveOp = nil;
    }
}


#pragma mark -
#pragma mark TXT RECORD:


- (NSDictionary*) txtRecord
{
    [_netService startMonitoring];
    return _txtRecord;
}

- (void) txtRecordChanged
{
    // no-op (this is here for subclassers to override)
}

- (NSString*) txtStringForKey: (NSString*)key
{
    NSData *value = [self.txtRecord objectForKey: key];
    if( ! value )
        return nil;
    if( ! [value isKindOfClass: [NSData class]] ) {
        Warn(@"TXT dictionary has unexpected value type: %@",value.class);
        return nil;
    }
    NSString *str = [[NSString alloc] initWithData: value encoding: NSUTF8StringEncoding];
    if( ! str )
        str = [[NSString alloc] initWithData: value encoding: NSWindowsCP1252StringEncoding];
    return [str autorelease];
}


- (void)netService:(NSNetService *)sender didUpdateTXTRecordData:(NSData *)data
{
    NSDictionary *txtDict = [NSNetService dictionaryFromTXTRecordData: data];
    if( ! $equal(txtDict,_txtRecord) ) {
        LogTo(Bonjour,@"%@ got TXT record (%u bytes)",self,data.length);
        [self willChangeValueForKey: @"txtRecord"];
        setObj(&_txtRecord,txtDict);
        [self didChangeValueForKey: @"txtRecord"];
        [self txtRecordChanged];
    }
}


#pragma mark -
#pragma mark ADDRESS RESOLUTION:


#define kAddressResolveTimeout      10.0
#define kAddressExpirationInterval  60.0
#define kAddressErrorRetryInterval   5.0


- (NSSet*) addresses
{
    if( _addresses && CFAbsoluteTimeGetCurrent() >= _addressesExpireAt ) {
        setObj(&_addresses,nil);            // eww, toss 'em and get new ones
        [self resolve];
    }
    return _addresses;
}


- (MYBonjourResolveOperation*) resolve
{
    if( ! _resolveOp ) {
        LogTo(Bonjour,@"Resolving %@",self);
        _resolveOp = [[MYBonjourResolveOperation alloc] init];
        _resolveOp.service = self;
        [_resolveOp start];
        Assert(_netService);
        Assert(_netService.delegate=self);
        [_netService resolveWithTimeout: kAddressResolveTimeout];
    }
    return _resolveOp;
}

- (void) setAddresses: (NSSet*)addresses
{
    setObj(&_addresses,addresses);
}


- (void) _finishedResolving: (NSSet*)addresses expireIn: (NSTimeInterval)expirationInterval
{
    _addressesExpireAt = CFAbsoluteTimeGetCurrent() + expirationInterval;
    self.addresses = addresses;
    _resolveOp.addresses = addresses;
    [_resolveOp finish];
    [_resolveOp release];
    _resolveOp = nil;
}


- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    // Convert the raw sockaddrs into IPAddress objects:
    NSMutableSet *addresses = [NSMutableSet setWithCapacity: 2];
    for( NSData *rawAddr in _netService.addresses ) {
        IPAddress *addr = [[IPAddress alloc] initWithSockAddr: rawAddr.bytes];
        if( addr ) {
            [addresses addObject: addr];
            [addr release];
        }
    }
    LogTo(Bonjour,@"Resolved %@: %@",self,addresses);
    [self _finishedResolving: addresses expireIn: kAddressExpirationInterval];
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    LogTo(Bonjour,@"Error resolving %@ -- %@",self,errorDict);
    [self _finishedResolving: [NSArray array] expireIn: kAddressErrorRetryInterval];
}

- (void)netServiceDidStop:(NSNetService *)sender
{
    LogTo(Bonjour,@"Resolve stopped for %@",self);
    [self _finishedResolving: [NSArray array] expireIn: kAddressErrorRetryInterval];
}


@end




@implementation MYBonjourResolveOperation

@synthesize service=_service, addresses=_addresses;

- (void) dealloc
{
    [_addresses release];
    [super dealloc];
}

@end


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
