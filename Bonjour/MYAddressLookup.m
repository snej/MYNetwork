//
//  MYAddressLookup.m
//  MYNetwork
//
//  Created by Jens Alfke on 4/24/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import "MYAddressLookup.h"
#import "IPAddress.h"
#import "ExceptionUtils.h"
#import "Test.h"
#import "Logging.h"
#import <dns_sd.h>


@implementation MYAddressLookup

- (id) initWithHostname: (NSString*)hostname
{
    self = [super init];
    if (self != nil) {
        if (!hostname) {
            [self release];
            return nil;
        }
        _hostname = [hostname copy];
        _addresses = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void) dealloc
{
    [_hostname release];
    [_addresses release];
    [super dealloc];
}


- (NSString*) description
{
    return $sprintf(@"%@[%@]", self.class,_hostname);
}


@synthesize port=_port, interfaceIndex=_interfaceIndex, addresses=_addresses;


- (NSTimeInterval) timeToLive {
    return MAX(0.0, _expires - CFAbsoluteTimeGetCurrent());
}


- (void) priv_resolvedAddress: (const struct sockaddr*)sockaddr
                          ttl: (uint32_t)ttl
                        flags: (DNSServiceFlags)flags
{
    HostAddress *address = [[HostAddress alloc] initWithHostname: _hostname 
                                                        sockaddr: sockaddr
                                                            port: _port];
    if (address) {
        if (flags & kDNSServiceFlagsAdd)
            [_addresses addObject: address];
        else
            [_addresses removeObject: address];
        [address release];
    }
    
    _expires = CFAbsoluteTimeGetCurrent() + ttl;

    if (!(flags & kDNSServiceFlagsMoreComing))
        LogTo(DNS,@"Got addresses of %@: %@ [TTL = %u]", self, _addresses, ttl);
}


static void lookupCallback(DNSServiceRef                    sdRef,
                           DNSServiceFlags                  flags,
                           uint32_t                         interfaceIndex,
                           DNSServiceErrorType              errorCode,
                           const char                       *hostname,
                           const struct sockaddr            *address,
                           uint32_t                         ttl,
                           void                             *context)
{
    MYAddressLookup *lookup = context;
    @try{
        //LogTo(Bonjour, @"lookupCallback for %s (err=%i)", hostname,errorCode);
        if (errorCode)
            [lookup setError: errorCode];
        else
            [lookup priv_resolvedAddress: address ttl: ttl flags: flags];
    }catchAndReport(@"MYDNSLookup query callback");
}


- (DNSServiceRef) createServiceRef {
    [_addresses removeAllObjects];
    DNSServiceRef serviceRef = NULL;
    self.error = DNSServiceGetAddrInfo(&serviceRef, 0,
                                       _interfaceIndex, 0,
                                       _hostname.UTF8String,
                                       &lookupCallback, self);
    return serviceRef;
}


@end



TestCase(MYDNSLookup) {
    EnableLogTo(Bonjour,YES);
    EnableLogTo(DNS,YES);
    [NSRunLoop currentRunLoop]; // create runloop

    MYAddressLookup *lookup = [[MYAddressLookup alloc] initWithHostname: @"www.apple.com" port: 80];
    [lookup start];
    
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 10]];
    [lookup release];
}    
