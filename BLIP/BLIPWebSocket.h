//
//  BLIPWebSocket.h
//  MYNetwork
//
//  Created by Jens Alfke on 4/1/13.
//
//

#import <Foundation/Foundation.h>

@class BLIPRequest, BLIPResponse, BLIPDispatcher;
@protocol BLIPWebSocketDelegate;


/** A BLIP connection layered on a WebSocket. */
@interface BLIPWebSocket : NSObject <BLIPMessageSender>

// Protocols should be an array of strings that turn into Sec-WebSocket-Protocol.
- (id)initWithURLRequest:(NSURLRequest *)request protocols:(NSArray *)protocols;
- (id)initWithURLRequest:(NSURLRequest *)request;

// Some helper constructors.
- (id)initWithURL:(NSURL *)url protocols:(NSArray *)protocols;
- (id)initWithURL:(NSURL *)url;

@property (nonatomic, weak) id<BLIPWebSocketDelegate> delegate;

- (void)open;
- (void)close;

/** Creates a new, empty outgoing request.
    You should add properties and/or body data to the request, before sending it by
    calling its -send method. */
- (BLIPRequest*) request;

/** Creates a new outgoing request.
    The body or properties may be nil; you can add additional data or properties by calling
    methods on the request itself, before sending it by calling its -send method. */
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



/** The delegate messages that BLIPWebSocketDelegate will send.
    All methods are optional. */
@protocol BLIPWebSocketDelegate <NSObject>
@optional

- (void)blipWebSocketDidOpen:(BLIPWebSocket*)webSocket;

- (void)blipWebSocket: (BLIPWebSocket*)webSocket didFailWithError:(NSError *)error;

- (void)blipWebSocket: (BLIPWebSocket*)webSocket
     didCloseWithCode:(NSInteger)code
               reason:(NSString *)reason
             wasClean:(BOOL)wasClean;

/** Called when a BLIPRequest is received from the peer, if there is no BLIPDispatcher
    rule to handle it.
    If the delegate wants to accept the request it should return YES; if it returns NO,
    a kBLIPError_NotFound error will be returned to the sender.
    The delegate should get the request's response object, fill in its data and properties
    or error property, and send it.
    If it doesn't explicitly send a response, a default empty one will be sent;
    to prevent this, call -deferResponse on the request if you want to send a response later. */
- (BOOL) blipWebSocket: (BLIPWebSocket*)webSocket receivedRequest: (BLIPRequest*)request;

/** Called when a BLIPResponse (to one of your requests) is received from the peer.
    This is called <i>after</i> the response object's onComplete target, if any, is invoked.*/
- (void) blipWebSocket: (BLIPWebSocket*)webSocket receivedResponse: (BLIPResponse*)response;

@end
