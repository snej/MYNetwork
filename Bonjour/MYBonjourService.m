//
//  MYBonjourService.m
//  MYNetwork
//
//  Created by Jens Alfke on 1/22/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import "MYBonjourService.h"
#import "MYBonjourQuery.h"
#import "MYAddressLookup.h"
#import "IPAddress.h"
#import "ConcurrentOperation.h"
#import "Test.h"
#import "Logging.h"
#import "ExceptionUtils.h"
#import <dns_sd.h>


NSString* const kBonjourServiceResolvedAddressesNotification = @"BonjourServiceResolvedAddresses";


@interface MYBonjourService ()
@end


@implementation MYBonjourService


- (id) initWithName: (NSString*)serviceName
               type: (NSString*)type
             domain: (NSString*)domain
          interface: (uint32)interfaceIndex
{
    self = [super init];
    if (self != nil) {
        _name = [serviceName copy];
        _type = [type copy];
        _domain = [domain copy];
        _interfaceIndex = interfaceIndex;
    }
    return self;
}

- (void) dealloc {
    [_name release];
    [_type release];
    [_domain release];
    [_hostname release];
    [_txtQuery stop];
    [_txtQuery release];
    [_addressLookup stop];
    [_addressLookup release];
    [super dealloc];
}


@synthesize name=_name, type=_type, domain=_domain, interfaceIndex=_interfaceIndex;


- (NSString*) description {
    return $sprintf(@"%@['%@'.%@%@]", self.class,_name,_type,_domain);
}


- (NSComparisonResult) compare: (id)obj {
    return [_name caseInsensitiveCompare: [obj name]];
}

- (BOOL) isEqual: (id)obj {
    if ([obj isKindOfClass: [MYBonjourService class]]) {
        MYBonjourService *service = obj;
        return [_name caseInsensitiveCompare: [service name]] == 0
            && $equal(_type, service->_type)
            && $equal(_domain, service->_domain)
            && _interfaceIndex == service->_interfaceIndex;
    } else {
        return NO;
    }
}

- (NSUInteger) hash {
    return _name.hash ^ _type.hash ^ _domain.hash;
}


- (void) added {
    LogTo(Bonjour,@"Added %@",self);
}

- (void) removed {
    LogTo(Bonjour,@"Removed %@",self);
    [self stop];
    
    [_txtQuery stop];
    [_txtQuery release];
    _txtQuery = nil;
    
    [_addressLookup stop];
}


- (void) priv_finishResolve {
    // If I haven't finished my resolve yet, run it synchronously now so I can return a valid value:
    if (!_startedResolve )
        [self start];
    if (self.serviceRef)
        [self waitForReply];
}    

- (NSString*) fullName {
    if (!_fullName) [self priv_finishResolve];
    return _fullName;
}

- (NSString*) hostname {
    if (!_hostname) [self priv_finishResolve];
    return _hostname;
}

- (UInt16) port {
    if (!_port) [self priv_finishResolve];
    return _port;
}


#pragma mark -
#pragma mark TXT RECORD:


- (NSDictionary*) txtRecord {
    // If I haven't started my resolve yet, start it now. (_txtRecord will be nil till it finishes.)
    if (!_startedResolve)
        [self start];
    return _txtRecord;
}

- (void) txtRecordChanged {
    // no-op (this is here for subclassers to override)
}

- (NSString*) txtStringForKey: (NSString*)key {
    NSData *value = [self.txtRecord objectForKey: key];
    if( ! value )
        return nil;
    if( ! [value isKindOfClass: [NSData class]] ) {
        Warn(@"TXT dictionary has unexpected value type: %@",value.class);
        return nil;
    }
    NSString *str = [[NSString alloc] initWithData: value encoding: NSUTF8StringEncoding];
    if( ! str )
        str = [[NSString alloc] initWithData: value encoding: NSWindowsCP1252StringEncoding];
    return [str autorelease];
}

- (void) setTxtData: (NSData*)txtData {
    NSDictionary *txtRecord = txtData ?[NSNetService dictionaryFromTXTRecordData: txtData] :nil;
    if (!$equal(txtRecord,_txtRecord)) {
        LogTo(Bonjour,@"%@ TXT = %@", self,txtRecord);
        [self willChangeValueForKey: @"txtRecord"];
        setObj(&_txtRecord, txtRecord);
        [self didChangeValueForKey: @"txtRecord"];
        [self txtRecordChanged];
    }
}


- (void) queryDidUpdate: (MYBonjourQuery*)query {
    if (query==_txtQuery)
        [self setTxtData: query.recordData];
}


#pragma mark -
#pragma mark FULLNAME/HOSTNAME/PORT RESOLUTION:


- (void) priv_resolvedFullName: (NSString*)fullName
                      hostname: (NSString*)hostname
                          port: (uint16_t)port
                     txtRecord: (NSData*)txtData
{
    LogTo(Bonjour, @"%@: fullname='%@', hostname=%@, port=%u, txt=%u bytes", 
          self, fullName, hostname, port, txtData.length);

    // Don't call a setter method to set these properties: the getters are synchronous, so
    // I might already be blocked in a call to one of them, in which case creating a KV
    // notification could cause trouble...
    _fullName = fullName.copy;
    _hostname = hostname.copy;
    _port = port;
    
    // TXT getter is async, though, so I can use a setter to announce the data's availability:
    [self setTxtData: txtData];
    
    // Now that I know my full name, I can start a persistent query to track the TXT:
    _txtQuery = [[MYBonjourQuery alloc] initWithBonjourService: self 
                                                    recordType: kDNSServiceType_TXT];
    _txtQuery.continuous = YES;
    [_txtQuery start];
}


static void resolveCallback(DNSServiceRef                       sdRef,
                            DNSServiceFlags                     flags,
                            uint32_t                            interfaceIndex,
                            DNSServiceErrorType                 errorCode,
                            const char                          *fullname,
                            const char                          *hosttarget,
                            uint16_t                            port,
                            uint16_t                            txtLen,
                            const unsigned char                 *txtRecord,
                            void                                *context)
{
    MYBonjourService *service = context;
    @try{
        //LogTo(Bonjour, @"resolveCallback for %@ (err=%i)", service,errorCode);
        if (errorCode) {
            [service setError: errorCode];
        } else {
            NSData *txtData = nil;
            if (txtRecord)
                txtData = [NSData dataWithBytes: txtRecord length: txtLen];
            [service priv_resolvedFullName: [NSString stringWithUTF8String: fullname]
                                  hostname: [NSString stringWithUTF8String: hosttarget]
                                      port: ntohs(port)
                                 txtRecord: txtData];
        }
    }catchAndReport(@"MYBonjourResolver query callback");
}


- (DNSServiceRef) createServiceRef {
    _startedResolve = YES;
    DNSServiceRef serviceRef = NULL;
    self.error = DNSServiceResolve(&serviceRef, 0,
                                   _interfaceIndex, 
                                   _name.UTF8String, _type.UTF8String, _domain.UTF8String,
                                   &resolveCallback, self);
    return serviceRef;
}


- (MYAddressLookup*) addressLookup {
    if (!_addressLookup) {
        // Create the lookup the first time this is called:
        _addressLookup = [[MYAddressLookup alloc] initWithHostname: self.hostname];
        _addressLookup.port = _port;
        _addressLookup.interfaceIndex = _interfaceIndex;
    }
    // (Re)start the lookup if it's expired:
    if (_addressLookup && _addressLookup.timeToLive <= 0.0)
        [_addressLookup start];
    return _addressLookup;
}


- (MYBonjourQuery*) queryForRecord: (UInt16)recordType {
    MYBonjourQuery *query = [[[MYBonjourQuery alloc] initWithBonjourService: self recordType: recordType]
                                 autorelease];
    return [query start] ?query :nil;
}


@end



/*
 Copyright (c) 2008-2009, Jens Alfke <jens@mooseyard.com>. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted
 provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions
 and the following disclaimer in the documentation and/or other materials provided with the
 distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRI-
 BUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR 
  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF 
 THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
