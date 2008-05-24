//
//  BLIPConnection.h
//  MYNetwork
//
//  Created by Jens Alfke on 5/10/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import "TCPConnection.h"
#import "TCPListener.h"
@class BLIPRequest, BLIPResponse, BLIPDispatcher;
@protocol BLIPConnectionDelegate;


/** Represents a connection to a peer, using the BLIP protocol over a TCP socket.
    Outgoing connections are made simply by instantiating a BLIPConnection via -initToAddress:.
    Incoming connections are usually set up by a BLIPListener and passed to the listener's
    delegate.
    Most of the API is inherited from TCPConnection. */
@interface BLIPConnection : TCPConnection
{
    BLIPDispatcher *_dispatcher;
}

/** The delegate object that will be called when the connection opens, closes or receives messages. */
@property (assign) id<BLIPConnectionDelegate> delegate;

@property (readonly) BLIPDispatcher *dispatcher;

/** Creates an outgoing request, with no properties.
    The body may be nil.
    To send it, call -send. */
- (BLIPRequest*) requestWithBody: (NSData*)body;

/** Creates an outgoing request.
    The body or properties may be nil.
    To send it, call -send. */
- (BLIPRequest*) requestWithBody: (NSData*)body
                      properties: (NSDictionary*)properies;

/** Sends a request over this connection.
    (Actually, it queues it to be sent; this method always returns immediately.)
    Call this instead of calling -send on the request itself, if the request was created with
    +[BLIPRequest requestWithBody:] and hasn't yet been assigned to any connection.
    This method will assign it to this connection before sending it.
    The request's matching response object will be returned, or nil if the request couldn't be sent. */
- (BLIPResponse*) sendRequest: (BLIPRequest*)request;
@end



/** The delegate messages that BLIPConnection will send,
    in addition to the ones inherited from TCPConnectionDelegate. */
@protocol BLIPConnectionDelegate <TCPConnectionDelegate>

/** Called when a BLIPRequest is received from the peer, if there is no BLIPDispatcher
    rule to handle it.
    The delegate should get the request's response object, fill in its data and properties
    or error property, and send it.
    If it doesn't explicitly send a response, a default empty one will be sent;
    to prevent this, call -deferResponse on the request if you want to send a response later. */
- (void) connection: (BLIPConnection*)connection receivedRequest: (BLIPRequest*)request;

@optional
/** Called when a BLIPResponse (to one of your requests) is received from the peer.
    This is called <i>after</i> the response object's onComplete target, if any, is invoked. */
- (void) connection: (BLIPConnection*)connection receivedResponse: (BLIPResponse*)response;
@end




/** A "server" that listens on a TCP socket for incoming BLIP connections and creates
    BLIPConnection instances to handle them.
    Most of the API is inherited from TCPListener. */
@interface BLIPListener : TCPListener
{
    BLIPDispatcher *_dispatcher;
}

@property (readonly) BLIPDispatcher *dispatcher;

@end
