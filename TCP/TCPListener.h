//
//  TCPListener.m
//  MYNetwork
//
//  Created by Jens Alfke on 5/10/08.
//  Copyright 2008 Jens Alfke. All rights reserved.

#import "TCPEndpoint.h"
@class TCPConnection, IPAddress;
@protocol TCPListenerDelegate;


/** Generic TCP-based server that listens for incoming connections on a port.
    For each incoming connection, it creates an instance of (a subclass of) the generic TCP
    client class TCPClient. The -connectionClass property lets you customize which subclass
    to use.
    TCPListener supports Bonjour advertisements for the service, and automatic port renumbering
    if there are conflicts. */
@interface TCPListener : TCPEndpoint 
{
    @private
    uint16_t _port;
    BOOL _pickAvailablePort;
    BOOL _useIPv6;
    CFSocketRef _ipv4socket;
    CFSocketRef _ipv6socket;
    
    NSString *_bonjourServiceType, *_bonjourServiceName;
    NSNetService *_netService;
    NSDictionary *_bonjourTXTRecord;
    BOOL _bonjourPublished;
    NSInteger /*NSNetServicesError*/ _bonjourError;

    Class _connectionClass;
}

/** Initializes a new TCPListener that will listen on the given port when opened. */
- (id) initWithPort: (UInt16)port;

/** The subclass of TCPConnection that will be instantiated. */
@property Class connectionClass;

@property (assign) id<TCPListenerDelegate> delegate;

/** Should the server listen for IPv6 connections (on the same port number)? Defaults to NO. */
@property BOOL useIPv6;

/** The port number to listen on.
    If the pickAvailablePort property is enabled, this value may be updated after the server opens
    to reflect the actual port number being used. */
@property uint16_t port;

/** Should the server pick a higher port number if the desired port is already in use?
    Defaults to NO. If enabled, the port number will be incremented until a free port is found. */
@property BOOL pickAvailablePort;

/** Opens the server. You must call this after configuring all desired properties (property
    changes are ignored while the server is open.) */
- (BOOL) open: (NSError **)error;

- (BOOL) open;

/** Closes the server. */
- (void) close;

/** Is the server currently open? */
@property (readonly) BOOL isOpen;


#pragma mark BONJOUR:

/** The Bonjour service type to advertise. Defaults to nil; setting it implicitly enables Bonjour.
    The value should look like e.g. "_http._tcp."; for details, see the NSNetService documentation. */
@property (copy) NSString *bonjourServiceType;

/** The Bonjour service name to advertise. Defaults to nil, meaning that a default name will be
    automatically generated if Bonjour is enabled (by setting -bonjourServiceType). */
@property (copy) NSString *bonjourServiceName;

/** The dictionary form of the Bonjour TXT record: metadata about the service that can be browsed
    by peers. Changes to this dictionary will be pushed in near-real-time to interested peers. */
@property (copy) NSDictionary *bonjourTXTRecord;

/** Is this service currently published/advertised via Bonjour? */
@property (readonly) BOOL bonjourPublished;

/** Current error status of Bonjour service advertising. See NSNetServicesError for error codes. */
@property (readonly) NSInteger /*NSNetServicesError*/ bonjourError;


@end



#pragma mark -

/** The delegate messages sent by TCPListener. */
@protocol TCPListenerDelegate <NSObject>

- (void) listener: (TCPListener*)listener didAcceptConnection: (TCPConnection*)connection;

@optional
- (void) listenerDidOpen: (TCPListener*)listener;
- (void) listener: (TCPListener*)listener failedToOpen: (NSError*)error;
- (void) listenerDidClose: (TCPListener*)listener;
- (BOOL) listener: (TCPListener*)listener shouldAcceptConnectionFrom: (IPAddress*)address;
@end
