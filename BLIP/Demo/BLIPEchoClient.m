//
//  BLIPEchoClient.m
//  MYNetwork
//
//  Created by Jens Alfke on 5/24/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//  Adapted from Apple sample code "CocoaEcho".
//

#import "BLIPEchoClient.h"
#import "BLIP.h"
#import "IPAddress.h"
#import "Target.h"


@implementation BLIPEchoClient

@synthesize serviceList=_serviceList;

- (void)awakeFromNib 
{
    _serviceBrowser = [[NSNetServiceBrowser alloc] init];
    _serviceList = [[NSMutableArray alloc] init];
    [_serviceBrowser setDelegate:self];
    
    [_serviceBrowser searchForServicesOfType:@"_blipecho._tcp." inDomain:@""];
}

#pragma mark -
#pragma mark BLIPConnection support

- (void)openConnection: (IPAddress*)address 
{
    _connection = [[BLIPConnection alloc] initToAddress: address];
    [_connection open];
}

- (void)closeConnection
{
    [_connection close];
    [_connection release];
    _connection = nil;
}

#pragma mark -
#pragma mark NSNetServiceBrowser delegate methods

// We broadcast the willChangeValueForKey: and didChangeValueForKey: for the NSTableView binding to work.

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
    if (![_serviceList containsObject:aNetService]) {
        [self willChangeValueForKey:@"serviceList"];
        [_serviceList addObject:aNetService];
        [self didChangeValueForKey:@"serviceList"];
    }
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
    if ([_serviceList containsObject:aNetService]) {
        [self willChangeValueForKey:@"serviceList"];
        [_serviceList removeObject:aNetService];
        [self didChangeValueForKey:@"serviceList"];
    }
}

#pragma mark -
#pragma mark NSNetService delegate methods

- (void)stopResolving
{
    if( _resolvingService ) {
        _resolvingService.delegate = nil;
        [_resolvingService stop];
        [_resolvingService release];
        _resolvingService = nil;
    }
}    

- (void)startResolving: (NSNetService*)service
{
    [self stopResolving];
    _resolvingService = [service retain];
    _resolvingService.delegate = self;
    [_resolvingService resolveWithTimeout: 5.0];
    
}

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    if( sender == _resolvingService ) {
        NSArray *addresses = _resolvingService.addresses;
        if( addresses.count > 0 ) {
            NSData *addressData = [addresses objectAtIndex: 0];
            IPAddress *address = [[IPAddress alloc] initWithSockAddr: addressData.bytes];
            [self openConnection: address];
            [address release];
        }
        [self stopResolving];
    }
}

#pragma mark -
#pragma mark GUI action methods

- (IBAction)serverClicked:(id)sender {
    NSTableView * table = (NSTableView *)sender;
    int selectedRow = [table selectedRow];
    
    [self closeConnection];
    [self stopResolving];
    
    if (-1 != selectedRow) {
        [self startResolving: [_serviceList objectAtIndex:selectedRow]];
    }
}

- (IBAction)sendText:(id)sender 
{
    BLIPRequest *r = [_connection requestWithBody: nil];
    r.bodyString = [sender stringValue];
    BLIPResponse *response = [r send];
    response.onComplete = $target(self,gotResponse:);
}

- (void) gotResponse: (BLIPResponse*)response
{
    [responseField setObjectValue: response.bodyString];
}    


@end

int main(int argc, char *argv[])
{
    return NSApplicationMain(argc,  (const char **) argv);
}
