//
//  TCPEndpoint.h
//  MYNetwork
//
//  Created by Jens Alfke on 5/14/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>


// SSL properties:
#define kTCPPropertySSLCertificates  ((NSString*)kCFStreamSSLCertificates)
#define kTCPPropertySSLAllowsAnyRoot ((NSString*)kCFStreamSSLAllowsAnyRoot)
extern NSString* const kTCPPropertySSLClientSideAuthentication;    // value is SSLAuthenticate enum


/** Abstract base class of TCPConnection and TCPListener.
    Mostly just manages the SSL properties. */
@interface TCPEndpoint : NSObject
{
    NSMutableDictionary *_sslProperties;
    id _delegate;
}

/** The desired security level. Use the security level constants from NSStream.h,
    such as NSStreamSocketSecurityLevelNegotiatedSSL. */
@property (copy) NSString *securityLevel;

/** Detailed SSL settings. This is the same as CFStream's kCFStreamPropertySSLSettings
    property. */
@property (copy) NSMutableDictionary *SSLProperties;

/** Shortcut to set a single SSL property. */
- (void) setSSLProperty: (id)value 
                 forKey: (NSString*)key;

//protected:
- (void) tellDelegate: (SEL)selector withObject: (id)param;

@end
