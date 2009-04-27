//
//  MYBonjourService.h
//  MYNetwork
//
//  Created by Jens Alfke on 1/22/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import "MYDNSService.h"
#import "ConcurrentOperation.h"
@class MYBonjourQuery, MYAddressLookup;


/** Represents a Bonjour service discovered by a BonjourBrowser. */
@interface MYBonjourService : MYDNSService 
{
    @private
    NSString *_name, *_fullName, *_type, *_domain, *_hostname;
    uint32_t _interfaceIndex;
    BOOL _startedResolve;
    UInt16 _port;
    NSDictionary *_txtRecord;
    MYBonjourQuery *_txtQuery;
    MYAddressLookup *_addressLookup;
}

/** The service's name. */
@property (readonly) NSString *name;

/** The service's type. */
@property (readonly) NSString *type;

/** The service's domain. */
@property (readonly) NSString *domain;

@property (readonly, copy) NSString *hostname;

@property (readonly) UInt16 port;

@property (readonly) uint32_t interfaceIndex;

@property (readonly,copy) NSString* fullName;

/** The service's metadata dictionary, from its DNS TXT record */
@property (readonly,copy) NSDictionary *txtRecord;

/** A convenience to access a single property from the TXT record. */
- (NSString*) txtStringForKey: (NSString*)key;

/** Returns a MYDNSLookup object that resolves the IP address(es) of this service.
    Subsequent calls to this method will always return the same object. */
- (MYAddressLookup*) addressLookup;

/** Starts a new MYBonjourQuery for the specified DNS record type of this service.
    @param recordType  The DNS record type, e.g. kDNSServiceType_TXT; see the enum in <dns_sd.h>. */
- (MYBonjourQuery*) queryForRecord: (UInt16)recordType;


// Protected methods, for subclass use only:

// (for subclasses to override, but not call):
- (id) initWithName: (NSString*)serviceName
               type: (NSString*)type
             domain: (NSString*)domain
          interface: (uint32_t)interfaceIndex;

- (void) added;
- (void) removed;
- (void) txtRecordChanged;

// Internal:

- (void) queryDidUpdate: (MYBonjourQuery*)query;

@end



@interface MYBonjourResolveOperation : ConcurrentOperation
{
    MYBonjourService *_service;
    NSSet *_addresses;
}

@property (readonly) MYBonjourService *service;
@property (readonly,retain) NSSet *addresses;

@end
