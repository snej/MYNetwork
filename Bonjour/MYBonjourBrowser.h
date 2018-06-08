//
//  MYBonjourBrowser.h
//  MYNetwork
//
//  Created by Jens Alfke on 1/22/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

@class MYBonjourRegistration;


/** Searches for Bonjour services of a specific type. */
@interface MYBonjourBrowser : MYDNSService

/** Initializes a new MYBonjourBrowser.
    Call -start to begin browsing.
    @param serviceType  The name of the service type to look for, e.g. "_http._tcp". */
- (id) initWithServiceType: (NSString*)serviceType;

@property (weak) id delegate;

/** Is the browser currently browsing? */
@property (readonly) BOOL browsing;

/** The set of currently found services. These are instances of the serviceClass,
    which is MYBonjourService by default.
    This is KV-observable. */
@property (readonly) NSSet *services;

/** The class of objects to create to represent services.
    The default value is [MYBonjourService class]; you can change this, but only
    to a subclass of that. */
@property (strong) Class serviceClass;

/** My own registration for this service type.
    This object is created on demand and won't be started up until you tell it to.
    Before starting it, you'll need to set its port, and optionally its name.
    Your own registration will _not_ be visible in the set of services.*/
@property (readonly) MYBonjourRegistration *myRegistration;

@end
