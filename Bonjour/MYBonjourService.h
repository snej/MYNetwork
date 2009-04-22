//
//  MYBonjourService.h
//  MYNetwork
//
//  Created by Jens Alfke on 1/22/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ConcurrentOperation.h"
@class MYBonjourResolveOperation;


/** Represents a Bonjour service discovered by a BonjourBrowser. */
@interface MYBonjourService : NSObject 
{
    @private
    NSNetService *_netService;
    NSDictionary *_txtRecord;
    NSSet *_addresses;
    CFAbsoluteTime _addressesExpireAt;
    MYBonjourResolveOperation *_resolveOp;
}

/** The service's name. */
@property (readonly) NSString *name;

/** The service's metadata dictionary, from its DNS TXT record */
@property (readonly,copy) NSDictionary *txtRecord;

/** A convenience to access a single property from the TXT record. */
- (NSString*) txtStringForKey: (NSString*)key;

/** Returns a set of IPAddress objects; may be the empty set if address resolution failed,
    or nil if addresses have not been resolved yet (or expired).
    In the latter case, call -resolve and wait for the returned Operation to finish. */
@property (readonly,copy) NSSet* addresses;

/** Starts looking up the IP address(es) of this service.
    @return  The NSOperation representing the lookup; you can observe this to see when it
        completes, or you can observe the service's 'addresses' property. */
- (MYBonjourResolveOperation*) resolve;

/** The underlying NSNetSerice object. */
@property (readonly) NSNetService *netService;


// Protected methods, for subclass use only:

- (id) initWithNetService: (NSNetService*)netService;

// (for subclasses to override, but not call):
- (void) added;
- (void) removed;
- (void) txtRecordChanged;

@end



@interface MYBonjourResolveOperation : ConcurrentOperation
{
    MYBonjourService *_service;
    NSSet *_addresses;
}

@property (readonly) MYBonjourService *service;
@property (readonly,retain) NSSet *addresses;

@end
