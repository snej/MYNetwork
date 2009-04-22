//
//  MYPortMapper.m
//  MYNetwork
//
//  Created by Jens Alfke on 1/4/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import "MYPortMapper.h"
#import "IPAddress.h"
#import "CollectionUtils.h"
#import "Logging.h"
#import "ExceptionUtils.h"

#import <dns_sd.h>
#import <sys/types.h>
#import <sys/socket.h>
#import <net/if.h>
#import <netinet/in.h>
#import <ifaddrs.h>


NSString* const MYPortMapperChangedNotification = @"MYPortMapperChanged";


@interface MYPortMapper ()
// Redeclare these properties as settable, internally:
@property (readwrite) SInt32 error;
@property (retain) IPAddress* publicAddress, *localAddress;
// Private getter:
@property (readonly) void* _service;
- (void) priv_updateLocalAddress;
- (void) priv_disconnect;
@end


@implementation MYPortMapper


- (id) initWithLocalPort: (UInt16)localPort
{
    self = [super init];
    if (self != nil) {
        _localPort = localPort;
        _mapTCP = YES;
        [self priv_updateLocalAddress];
    }
    return self;
}

- (id) initWithNullMapping
{
    // A PortMapper with no port or protocols will cause the DNSService to look up 
    // our public address without creating a mapping.
    if ([self initWithLocalPort: 0]) {
        _mapTCP = _mapUDP = NO;
    }
    return self;
}


- (void) dealloc
{
    if( _service )
        [self priv_disconnect];
    [_publicAddress release];
    [_localAddress release];
    [super dealloc];
}

- (void) finalize
{
    if( _service )
        [self priv_disconnect];
    [super finalize];
}


@synthesize localAddress=_localAddress, publicAddress=_publicAddress,
            error=_error, _service=_service,
            mapTCP=_mapTCP, mapUDP=_mapUDP,
            desiredPublicPort=_desiredPublicPort;


- (BOOL) isMapped
{
    return ! $equal(_publicAddress,_localAddress);
}

- (void) priv_updateLocalAddress 
{
    IPAddress *localAddress = [IPAddress localAddressWithPort: _localPort];
    if (!$equal(localAddress,_localAddress))
        self.localAddress = localAddress;
}


static IPAddress* makeIPAddr( UInt32 rawAddr, UInt16 port ) {
    if (rawAddr)
        return [[[IPAddress alloc] initWithIPv4: rawAddr port: port] autorelease];
    else
        return nil;
}

/** Called whenever the port mapping changes (see comment for callback, below.) */
- (void) priv_portMapStatus: (DNSServiceErrorType)errorCode 
              publicAddress: (UInt32)rawPublicAddress
                 publicPort: (UInt16)publicPort
{
    LogTo(PortMapper,@"Callback got err %i, addr %08X:%hu",
          errorCode, rawPublicAddress, publicPort);
    if( errorCode==kDNSServiceErr_NoError ) {
        if( rawPublicAddress==0 || (publicPort==0 && (_mapTCP || _mapUDP)) ) {
            LogTo(PortMapper,@"(Callback reported no mapping available)");
            errorCode = kDNSServiceErr_NATPortMappingUnsupported;
        }
    }
    if( errorCode != self.error )
        self.error = errorCode;

    [self priv_updateLocalAddress];
    IPAddress *publicAddress = makeIPAddr(rawPublicAddress,publicPort);
    if (!$equal(publicAddress,_publicAddress))
        self.publicAddress = publicAddress;
    
    if( ! errorCode ) {
        LogTo(PortMapper,@"Callback got %08X:%hu -> %@ (mapped=%i)",
              rawPublicAddress,publicPort, self.publicAddress, self.isMapped);
    }
    [[NSNotificationCenter defaultCenter] postNotificationName: MYPortMapperChangedNotification
                                                        object: self];
}


/** Asynchronous callback from DNSServiceNATPortMappingCreate.
    This is invoked whenever the status of the port mapping changes.
    All it does is dispatch to the object's priv_portMapStatus:publicAddress:publicPort: method. */
static void portMapCallback (
                      DNSServiceRef                    sdRef,
                      DNSServiceFlags                  flags,
                      uint32_t                         interfaceIndex,
                      DNSServiceErrorType              errorCode,
                      uint32_t                         publicAddress,    /* four byte IPv4 address in network byte order */
                      DNSServiceProtocol               protocol,
                      uint16_t                         privatePort,
                      uint16_t                         publicPort,       /* may be different than the requested port */
                      uint32_t                         ttl,              /* may be different than the requested ttl */
                      void                             *context
                      )
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    @try{
        [(MYPortMapper*)context priv_portMapStatus: errorCode 
                                     publicAddress: publicAddress
                                        publicPort: ntohs(publicPort)];  // port #s in network byte order!
    }catchAndReport(@"PortMapper");
    [pool drain];
}


/** CFSocket callback, informing us that _socket has data available, which means
    that the DNS service has an incoming result to be processed. This will end up invoking
    the portMapCallback. */
static void serviceCallback(CFSocketRef s, 
                            CFSocketCallBackType type,
                            CFDataRef address, const void *data, void *clientCallBackInfo)
{
    MYPortMapper *mapper = (MYPortMapper*)clientCallBackInfo;
    DNSServiceRef service = mapper._service;
    DNSServiceErrorType err = DNSServiceProcessResult(service);
    if( err ) {
        // An error here means the socket has failed and should be closed.
        [mapper priv_portMapStatus: err publicAddress: 0 publicPort: 0];
        [mapper priv_disconnect];
    }
}



- (BOOL) open
{
    NSAssert(!_service,@"Already open");
    // Create the DNSService:
    DNSServiceProtocol protocols = 0;
    if( _mapTCP ) protocols |= kDNSServiceProtocol_TCP;
    if( _mapUDP ) protocols |= kDNSServiceProtocol_UDP;
    self.error = DNSServiceNATPortMappingCreate((DNSServiceRef*)&_service, 
                                         0 /*flags*/, 
                                         0 /*interfaceIndex*/, 
                                         protocols,
                                         htons(_localPort),
                                         htons(_desiredPublicPort),
                                         0 /*ttl*/,
                                         &portMapCallback, 
                                         self);
    if( _error ) {
        LogTo(PortMapper,@"Error %i creating port mapping",_error);
        return NO;
    }
    
    // Wrap a CFSocket around the service's socket:
    CFSocketContext ctxt = { 0, self, CFRetain, CFRelease, NULL };
    _socket = CFSocketCreateWithNative(NULL, 
                                       DNSServiceRefSockFD(_service), 
                                       kCFSocketReadCallBack, 
                                       &serviceCallback, &ctxt);
    if( _socket ) {
        CFSocketSetSocketFlags(_socket, CFSocketGetSocketFlags(_socket) & ~kCFSocketCloseOnInvalidate);
        // Attach the socket to the runloop so the serviceCallback will be invoked:
        _socketSource = CFSocketCreateRunLoopSource(NULL, _socket, 0);
        if( _socketSource )
            CFRunLoopAddSource(CFRunLoopGetCurrent(), _socketSource, kCFRunLoopCommonModes);
    }
    if( _socketSource ) {
        LogTo(PortMapper,@"Opening");
        return YES;
    } else {
        Warn(@"Failed to open PortMapper");
        [self close];
        _error = kDNSServiceErr_Unknown;
        return NO;
    }
}


- (BOOL) waitTillOpened
{
    if( ! _socketSource )
        if( ! [self open] )
            return NO;
    // Run the runloop until there's either an error or a result:
    while( _error==0 && _publicAddress==nil )
        if( ! [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                       beforeDate: [NSDate distantFuture]] )
            break;
    return (_error==0);
}


// Close down, but _without_ clearing the 'error' property
- (void) priv_disconnect
{
    if( _socketSource ) {
        CFRunLoopSourceInvalidate(_socketSource);
        CFRelease(_socketSource);
        _socketSource = NULL;
    }
    if( _socket ) {
        CFSocketInvalidate(_socket);
        CFRelease(_socket);
        _socket = NULL;
    }
    if( _service ) {
        LogTo(PortMapper,@"Deleting port mapping");
        DNSServiceRefDeallocate(_service);
        _service = NULL;
        self.publicAddress = nil;
    }
}

- (void) close
{
    [self priv_disconnect];
    self.error = 0;
}


+ (IPAddress*) findPublicAddress
{
    IPAddress *addr = nil;
    MYPortMapper *mapper = [[self alloc] initWithNullMapping];
    if( [mapper waitTillOpened] )
        addr = [mapper.publicAddress retain];
    [mapper close];
    [mapper release];
    return [addr autorelease];
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
