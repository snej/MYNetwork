//
//  MYAddressLookup.h
//  MYNetwork
//
//  Created by Jens Alfke on 4/24/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import "MYDNSService.h"


/** An asynchronous DNS address lookup. Supports both Bonjour services and traditional hostnames. */
@interface MYAddressLookup : MYDNSService
{
    NSString *_hostname;
    UInt16 _interfaceIndex;
    NSMutableSet *_addresses;
    UInt16 _port;
    CFAbsoluteTime _expires;
}

/** Initializes the lookup with a DNS hostname. */
- (id) initWithHostname: (NSString*)hostname;

/** The port number; this will be copied into the resulting IPAddress objects.
    Defaults to zero, but you can set it before calling -start. */
@property UInt16 port;

/** The index of the network interface. You usually don't need to set this. */
@property UInt16 interfaceIndex;

/** The resulting address(es) of the host, as HostAddress objects. */
@property (readonly) NSSet *addresses;

/** How much longer the addresses will remain valid.
    If the value is zero, the addresses are no longer valid, and you should instead
    call -start again and wait for the 'addresses' property to update.
    If you set the service to continuous mode, addresses will never expire since the
    query will continue to update them. */
@property (readonly) NSTimeInterval timeToLive;

@end
