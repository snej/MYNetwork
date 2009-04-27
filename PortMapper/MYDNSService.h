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
    BOOL _continuous;
}

/** If NO (the default), the service will stop after it gets a result.
    If YES, it will continue to run until stopped. */
@property BOOL continuous;

/** Starts the service.
    Returns immediately; you can find out when the service actually starts (or fails to)
    by observing the isOpen and error properties.
    It's very unlikely that this call itself will fail (return NO). If it does, it
    probably means that the mDNSResponder process isn't working. */
- (BOOL) start;

/** Stops the service. */
- (void) stop;


/** The error status, a DNSServiceErrorType enum; nonzero if something went wrong. 
    This property is KV observable. */
@property int32_t error;

// PROTECTED:

/** Subclass must implement this abstract method to create a new DNSServiceRef.
    This method is called by -open.
    If an error occurs, the method should set self.error and return NULL.*/
- (struct _DNSServiceRef_t*) createServiceRef;

@property (readonly) struct _DNSServiceRef_t* serviceRef;

/** Same as -stop, but does not clear the error property.
    (The stop method actually calls this first.) */
- (void) cancel;

/** Block until a message is received from the daemon.
    This will cause the service's callback (defined by the subclass) to be invoked.
    @return  YES if a message is received, NO on error (or if the service isn't started) */
- (BOOL) waitForReply;

@end
