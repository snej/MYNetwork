//
//  MYBonjourRegistration.m
//  MYNetwork
//
//  Created by Jens Alfke on 4/27/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import "MYBonjourRegistration.h"
#import "MYBonjourService.h"
#import "ExceptionUtils.h"
#import "Test.h"
#import "Logging.h"
#import <dns_sd.h>


#define kTXTTTL 60          // TTL in seconds for TXT records I register


@interface MYBonjourRegistration ()
@property BOOL registered;
- (void) _updateNullRecord;
@end


@implementation MYBonjourRegistration
{
    NSString *_name, *_type, *_domain;
    UInt16 _port;
    BOOL _autoRename;
    BOOL _registered;
    NSMutableDictionary *_txtRecord;
    NSData *_nullRecord;
    struct _DNSRecordRef_t *_nullRecordReg;
}


static NSMutableDictionary *sAllRegistrations;


+ (void) priv_addRegistration: (MYBonjourRegistration*)reg {
    if (!sAllRegistrations)
        sAllRegistrations = [[NSMutableDictionary alloc] init];
    sAllRegistrations[reg.fullName] = reg;
}

+ (void) priv_removeRegistration: (MYBonjourRegistration*)reg {
    [sAllRegistrations removeObjectForKey: reg.fullName];
}

+ (MYBonjourRegistration*) registrationWithFullName: (NSString*)fullName {
    return sAllRegistrations[fullName];
}


- (id) initWithServiceType: (NSString*)serviceType port: (UInt16)port
{
    self = [super init];
    if (self != nil) {
        self.continuous = YES;
        self.usePrivateConnection = YES;    // DNSServiceUpdateRecord doesn't work with shared conn :(
        _type = [serviceType copy];
        _port = port;
        _autoRename = YES;
    }
    return self;
}



@synthesize name=_name, type=_type, domain=_domain, port=_port, autoRename=_autoRename;
@synthesize registered=_registered;


- (NSString*) fullName {
    return [[self class] fullNameOfService: _name ofType: _type inDomain: _domain];
}


- (BOOL) isSameAsService: (MYBonjourService*)service {
    return _name && _domain && [self.fullName isEqualToString: service.fullName];
}


- (NSString*) description
{
    return $sprintf(@"%@['%@'.%@%@]", self.class,_name,_type,_domain);
}


- (void) priv_registeredAsName: (NSString*)name 
                          type: (NSString*)regtype
                        domain: (NSString*)domain
{
    if (!$equal(name,_name))
        self.name = name;
    if (!$equal(domain,_domain))
        self.domain = domain;
    LogTo(Bonjour,@"Registered %@", self);
    self.registered = YES;
    [[self class] priv_addRegistration: self];
}


static void regCallback(DNSServiceRef                       sdRef,
                        DNSServiceFlags                     flags,
                        DNSServiceErrorType                 errorCode,
                        const char                          *name,
                        const char                          *regtype,
                        const char                          *domain,
                        void                                *context)
{
    MYBonjourRegistration *reg = (__bridge MYBonjourRegistration *)(context);
    @try{
        if (!errorCode)
            [reg priv_registeredAsName: @(name)
                                  type: @(regtype)
                                domain: @(domain)];
    }catchAndReport(@"MYBonjourRegistration callback");
    [reg gotResponse: errorCode];
}


- (DNSServiceErrorType) createServiceRef: (DNSServiceRef*)sdRefPtr {
    DNSServiceFlags flags = 0;
    if (!_autoRename)
        flags |= kDNSServiceFlagsNoAutoRename;
    NSData *txtData = nil;
    if (_txtRecord)
        txtData = [NSNetService dataFromTXTRecordDictionary: _txtRecord];
    DNSServiceErrorType err;
    err = DNSServiceRegister(sdRefPtr,
                              flags,
                              0,
                              _name.UTF8String,         // _name is likely to be nil
                              _type.UTF8String,
                              _domain.UTF8String,       // _domain is most likely nil
                              NULL,
                              htons(_port),
                              txtData.length,
                              txtData.bytes,
                              &regCallback,
                              (__bridge void *)(self));
    if (!err && _nullRecord)
        [self _updateNullRecord];
    return err;
}


- (void) cancel {
    if (_nullRecordReg && self.serviceRef) {
        DNSServiceRemoveRecord(self.serviceRef, _nullRecordReg, 0);
        _nullRecordReg = NULL;
    }
    
    [super cancel];
  
    if (_registered) {
        [[self class] priv_removeRegistration: self];
        self.registered = NO;
    }
}


#pragma mark 
#pragma mark TXT RECORD:


+ (NSData*) dataFromTXTRecordDictionary: (NSDictionary*)txtDict {
    if (!txtDict)
        return nil;
    // First translate any non-NSData values into UTF-8 formatted description data:
    NSMutableDictionary *encodedDict = $mdict();
    for (NSString *key in txtDict) {
        if (![key isKindOfClass: [NSString class]]) {
            Warn(@"TXT dictionary cannot have %@ as key", [key class]);
            return nil;
        }
        id value = txtDict[key];
        if (![value isKindOfClass: [NSData class]]) {
            value = [[value description] dataUsingEncoding: NSUTF8StringEncoding];
        }
        if ([value length] > 255) {
            Warn(@"TXT dict value for '%@' is too long (%lu bytes)", key, (unsigned long)[value length]);
            return nil;
        }
        encodedDict[key] = value;
    }
    return [NSNetService dataFromTXTRecordDictionary: encodedDict];
}


static NSInteger compareData (id data1, id data2, void *context) {
    size_t length1 = [data1 length], length2 = [data2 length];
    int result = memcmp([data1 bytes], [data2 bytes], MIN(length1,length2));
    if (result==0) {
        if (length1>length2)
            result = 1;
        else if (length1<length2)
            result = -1;
    }
    return result;
}

+ (NSData*) canonicalFormOfTXTRecordDictionary: (NSDictionary*)txtDict
{
    if (!txtDict)
        return nil;
    
    // First convert keys and values to NSData:
    NSMutableDictionary *dataDict = $mdict();
    for (NSString *key in txtDict) {
        if (![key hasPrefix: @"("]) {               // ignore parenthesized keys
            if (![key isKindOfClass: [NSString class]]) {
                Warn(@"TXT dictionary cannot have %@ as key", [key class]);
                return nil;
            }
            NSData *keyData = [key dataUsingEncoding: NSUTF8StringEncoding];
            if (keyData.length > 255) {
                Warn(@"TXT dictionary key too long: %@", key);
                return nil;
            }
            id value = txtDict[key];
            if (![value isKindOfClass: [NSData class]]) {
                value = [[value description] dataUsingEncoding: NSUTF8StringEncoding];
            }
            if ([value length] > 255) {
                Warn(@"TXT dictionary value too long: %@", value);
                return nil;
            }
            dataDict[keyData] = value;
        }
    }
    
    // Add key/value pairs, sorted by increasing key:
    NSMutableData *canonical = [NSMutableData dataWithCapacity: 1000];
    for (NSData *key in [[dataDict allKeys] sortedArrayUsingFunction: compareData context: NULL]) {
        // Append key prefixed with length:
        UInt8 length = [key length];
        [canonical appendBytes: &length length: sizeof(length)];
        [canonical appendData: key];
        // Append value prefixed with length:
        NSData *value = dataDict[key];
        length = [value length];
        [canonical appendBytes: &length length: sizeof(length)];
        [canonical appendData: value];
    }
    return canonical;
}


- (void) updateTXTRecord {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(updateTXTRecord) object: nil];
    if (self.serviceRef) {
        NSData *data = [[self class] dataFromTXTRecordDictionary: _txtRecord];
        Assert(data!=nil || _txtRecord==nil, @"Can't convert dictionary to TXT record: %@", _txtRecord);
        DNSServiceErrorType err = DNSServiceUpdateRecord(self.serviceRef,
                                                         NULL,
                                                         0,
                                                         data.length,
                                                         data.bytes,
                                                         kTXTTTL);
        if (err)
            Warn(@"%@ failed to update TXT (err=%i)", self,err);
        else
            LogTo(Bonjour,@"%@ updated TXT to %lu bytes: %@", self,(unsigned long)data.length,data);
    }
}


- (NSDictionary*) TXTRecord {
    return _txtRecord;
}

- (void) setTXTRecord: (NSDictionary*)txtDict {
    if (!$equal(_txtRecord,txtDict)) {
         _txtRecord = [ txtDict copy];
        [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(updateTXTRecord) object: nil];
        [self performSelector: @selector(updateTXTRecord) withObject: nil afterDelay: 0.1];
    }
}

- (void) setString: (NSString*)value forTXTKey: (NSString*)key
{
    NSData *data = [value dataUsingEncoding: NSUTF8StringEncoding];
    if (!$equal(data, _txtRecord[key])) {
        if (data) {
            if (!_txtRecord) _txtRecord = [[NSMutableDictionary alloc] init];
            _txtRecord[key] = data;
        } else
            [_txtRecord removeObjectForKey: key];
        [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(updateTXTRecord) object: nil];
        [self performSelector: @selector(updateTXTRecord) withObject: nil afterDelay: 0.1];
    }
}


- (NSData*) nullRecord {
  return _nullRecord;
}

- (void) setNullRecord: (NSData*)nullRecord {
    if (!$equal(_nullRecord, nullRecord)) {
        _nullRecord = [nullRecord copy];
        if (self.serviceRef)
            [self _updateNullRecord];
    }
}


- (void) _updateNullRecord {
    DNSServiceRef serviceRef = self.serviceRef;
    Assert(serviceRef);
    DNSServiceErrorType err = 0;
    if (!_nullRecord) {
        if (_nullRecordReg) {
            err = DNSServiceRemoveRecord(serviceRef, _nullRecordReg, 0);
            _nullRecordReg = NULL;
        }
    } else if (!_nullRecordReg) {
        err = DNSServiceAddRecord(serviceRef, &_nullRecordReg, 0,
                                  kDNSServiceType_NULL, 
                                  _nullRecord.length, _nullRecord.bytes, 
                                  0);
    } else {
        err = DNSServiceUpdateRecord(serviceRef, _nullRecordReg, 0,
                                     _nullRecord.length, _nullRecord.bytes, 
                                     0);
    }
    if (err)
        Warn(@"MYBonjourRegistration: Couldn't update NULL record, err=%i",err);
    else
        LogTo(DNS, @"MYBonjourRegistration: Set NULL record (%lu bytes) %@",
              (unsigned long)_nullRecord.length, _nullRecord);
}

@end




#pragma mark -
#pragma mark TESTING:

#if DEBUG

#import "MYBonjourQuery.h"
#import "MYAddressLookup.h"

@interface BonjourRegTester : NSObject
{
    MYBonjourRegistration *_reg;
    BOOL _updating;
}
@end

@implementation BonjourRegTester

- (void) updateTXT {
    NSDictionary *txt = $dict({@"time", $sprintf(@"%.3lf", CFAbsoluteTimeGetCurrent())});
    _reg.TXTRecord = txt;
    CAssertEqual(_reg.TXTRecord, txt);
    [self performSelector: @selector(updateTXT) withObject: nil afterDelay: 3.0];
}

- (id) init
{
    self = [super init];
    if (self != nil) {
        _reg = [[MYBonjourRegistration alloc] initWithServiceType: @"_foo._tcp" port: 12345];
        [_reg addObserver: self forKeyPath: @"registered" options: NSKeyValueObservingOptionNew context: NULL];
        [_reg addObserver: self forKeyPath: @"name" options: NSKeyValueObservingOptionNew context: NULL];
        
        [self updateTXT];
        [_reg start];
    }
    return self;
}

- (void) dealloc
{
    [_reg stop];
    [_reg removeObserver: self forKeyPath: @"registered"];
    [_reg removeObserver: self forKeyPath: @"name"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    LogTo(Bonjour,@"Observed change in %@: %@",keyPath,change);
}

@end

TestCase(BonjourReg) {
    EnableLogTo(Bonjour,YES);
    EnableLogTo(DNS,YES);
    [NSRunLoop currentRunLoop]; // create runloop
    __unused BonjourRegTester *tester = [[BonjourRegTester alloc] init];
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 15]];
    tester = nil;
}

#endif


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
