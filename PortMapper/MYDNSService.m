//
//  MYDNSService.m
//  MYNetwork
//
//  Created by Jens Alfke on 4/23/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import "MYDNSService.h"
#import "CollectionUtils.h"
#import "Logging.h"
#import "Test.h"
#import "ExceptionUtils.h"

#import <dns_sd.h>


static void serviceCallback(CFSocketRef s, 
                            CFSocketCallBackType type,
                            CFDataRef address,
                            const void *data,
                            void *clientCallBackInfo);


@implementation MYDNSService


- (void) dealloc
{
    if( _serviceRef )
        [self stopService];
    [super dealloc];
}

- (void) finalize
{
    if( _serviceRef )
        [self stopService];
    [super finalize];
}


@synthesize serviceRef=_serviceRef, error=_error;


- (DNSServiceRef) createServiceRef {
    AssertAbstractMethod();
}


- (BOOL) open
{
    if (_serviceRef)
        return YES;
    _serviceRef = [self createServiceRef];
    if (_serviceRef) {
        // Wrap a CFSocket around the service's socket:
        CFSocketContext ctxt = { 0, self, CFRetain, CFRelease, NULL };
        _socket = CFSocketCreateWithNative(NULL, 
                                           DNSServiceRefSockFD(_serviceRef), 
                                           kCFSocketReadCallBack, 
                                           &serviceCallback, &ctxt);
        if( _socket ) {
            CFSocketSetSocketFlags(_socket, CFSocketGetSocketFlags(_socket) & ~kCFSocketCloseOnInvalidate);
            // Attach the socket to the runloop so the serviceCallback will be invoked:
            _socketSource = CFSocketCreateRunLoopSource(NULL, _socket, 0);
            if( _socketSource ) {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), _socketSource, kCFRunLoopCommonModes);
                LogTo(DNS,@"Opening %@",self);
                return YES; // success
            }
        }
    }
    if (!_error)
        self.error = kDNSServiceErr_Unknown;
    LogTo(DNS,@"Failed to open %@ -- err=%i",self,_error);
    [self stopService];
    return NO;
}


- (void) stopService
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
    if( _serviceRef ) {
        LogTo(DNS,@"Stopped %@",self);
        DNSServiceRefDeallocate(_serviceRef);
        _serviceRef = NULL;
    }
}


- (void) close
{
    [self stopService];
    if (_error)
        self.error = 0;
}


/** CFSocket callback, informing us that _socket has data available, which means
    that the DNS service has an incoming result to be processed. This will end up invoking
    the service's specific callback. */
static void serviceCallback(CFSocketRef s, 
                            CFSocketCallBackType type,
                            CFDataRef address, const void *data, void *clientCallBackInfo)
{
    MYDNSService *serviceObj = (MYDNSService*)clientCallBackInfo;
    DNSServiceRef service = serviceObj.serviceRef;
    DNSServiceErrorType err = DNSServiceProcessResult(service);
    if( err ) {
        // An error here means the socket has failed and should be closed.
        serviceObj.error = err;
        [serviceObj stopService];
    }
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
