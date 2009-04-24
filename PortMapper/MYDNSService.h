//
//  MYDNSService.h
//  MYNetwork
//
//  Created by Jens Alfke on 4/23/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreFoundation/CFSocket.h>


/** Abstract superclass for services based on DNSServiceRefs, such as MYPortMapper. */
@interface MYDNSService : NSObject
{
    @private
    struct _DNSServiceRef_t *_serviceRef;
    CFSocketRef _socket;
    CFRunLoopSourceRef _socketSource;
    SInt32 _error;
}

/** Starts the service.
    Returns immediately; you can find out when the service actually starts (or fails to)
    by observing the isOpen and error properties.
    It's very unlikely that this call itself will fail (return NO). If it does, it
    probably means that the mDNSResponder process isn't working. */
- (BOOL) open;

- (void) close;


@property (readonly) struct _DNSServiceRef_t* serviceRef;

/** The error status, a DNSServiceErrorType enum; nonzero if something went wrong. 
    This property is KV observable. */
@property SInt32 error;

// PROTECTED:

/** Subclass must implement this abstract method to create a new DNSServiceRef.
    This method is called by -open.
    If an error occurs, the method should set self.error and return NULL.*/
- (struct _DNSServiceRef_t*) createServiceRef;

- (void) stopService;

@end
