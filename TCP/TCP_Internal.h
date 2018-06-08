//
//  TCP_Internal.h
//  MYNetwork
//
//  Created by Jens Alfke on 5/18/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//


#import "TCPWriter.h"
#import "TCPConnection.h"
#import "TCPListener.h"

/* Private declarations and APIs for TCP client/server implementation. */



@interface TCPConnection ()
- (void) _setStreamProperty: (id)value forKey: (NSString*)key;
- (void) _streamOpened: (TCPStream*)stream;
- (BOOL) _streamPeerCertAvailable: (TCPStream*)stream;
- (void) _stream: (TCPStream*)stream gotError: (NSError*)error;
- (void) _streamCanClose: (TCPStream*)stream;
- (void) _streamGotEOF: (TCPStream*)stream;
- (void) _streamDisconnected: (TCPStream*)stream;
@end


@interface TCPStream ()
{
    @protected
    __weak TCPConnection *_conn;
    NSStream *_stream;
    BOOL _shouldClose;
}
- (void) _unclose;
@end


@interface TCPEndpoint ()
{
    @protected
    NSMutableDictionary *_sslProperties;
    __weak id _delegate;
}
@end


@interface TCPEndpoint (Certificates)
+ (NSString*) describeCert: (SecCertificateRef)cert;
+ (NSString*) describeIdentity: (SecIdentityRef)identity;
@end
