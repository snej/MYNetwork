//
//  BLIPMessage.h
//  MYNetwork
//
//  Created by Jens Alfke on 5/10/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>
@class BLIPProperties, BLIPMutableProperties, BLIPRequest, BLIPResponse;


@protocol BLIPMessageSender <NSObject>
- (BOOL) _sendRequest: (BLIPRequest*)q response: (BLIPResponse*)response;
- (BOOL) _sendResponse: (BLIPResponse*)response;
@property (readonly) NSError* error;
@end


/** NSError domain and codes for BLIP */
extern NSString* const BLIPErrorDomain;
enum {
    kBLIPError_BadData = 1,
    kBLIPError_BadFrame,
    kBLIPError_Disconnected,
    kBLIPError_PeerNotAllowed,
    
    kBLIPError_Misc = 99,
    
    // errors returned in responses:
    kBLIPError_BadRequest = 400,
    kBLIPError_Forbidden = 403,
    kBLIPError_NotFound = 404,
    kBLIPError_BadRange = 416,
    
    kBLIPError_HandlerFailed = 501,
    kBLIPError_Unspecified = 599            // peer didn't send any detailed error info
};

NSError *BLIPMakeError( int errorCode, NSString *message, ... ) __attribute__ ((format (__NSString__, 2, 3)));


/** Abstract superclass for <a href=".#blipdesc">BLIP</a> requests and responses. */
@interface BLIPMessage : NSObject

/** The BLIPConnection or BLIPWebSocket associated with this message. */
@property (readonly,strong) id<BLIPMessageSender> connection;

/** This message's serial number in its connection.
    A BLIPRequest's number is initially zero, then assigned when it's sent.
    A BLIPResponse is automatically assigned the same number as the request it replies to. */
@property (readonly) UInt32 number;

/** Is this a message sent by me (as opposed to the peer)? */
@property (readonly) BOOL isMine;

/** Has this message been sent yet? (Only makes sense when isMine is true.) */
@property (readonly) BOOL sent;

/** Has enough of the message arrived to read its properies? */
@property (readonly) BOOL propertiesAvailable;

/** Has the entire message, including the body, arrived? */
@property (readonly) BOOL complete;

/** Should the message body be compressed with gzip?
    This property can only be set <i>before</i> sending the message. */
@property BOOL compressed;

/** Should the message be sent ahead of normal-priority messages?
    This property can only be set <i>before</i> sending the message. */
@property BOOL urgent;

/** Can this message be changed? (Only true for outgoing messages, before you send them.) */
@property (readonly) BOOL isMutable;

/** The message body, a blob of arbitrary data. */
@property (copy) NSData *body;

/** Appends data to the body. */
- (void) addToBody: (NSData*)data;

/** The message body as an NSString.
    The UTF-8 character encoding is used to convert. */
@property (copy) NSString *bodyString;

/** An arbitrary object that you can associate with this message for your own purposes.
    The message retains it, but doesn't do anything else with it. */
@property (strong) id representedObject;

#pragma mark PROPERTIES:

/** The message's properties, a dictionary-like object.
    Message properties are much like the headers in HTTP, MIME and RFC822. */
@property (readonly) BLIPProperties* properties;

/** Mutable version of the message's properties; only available if this mesage is mutable. */
@property (readonly) BLIPMutableProperties* mutableProperties;

/** The value of the "Content-Type" property, which is by convention the MIME type of the body. */
@property (copy) NSString *contentType;

/** The value of the "Profile" property, which by convention identifies the purpose of the message. */
@property (copy) NSString *profile;

@property (strong) void (^onPropertiesAvailable)(BLIPProperties*);

/** A shortcut to get the value of a property. */
- (NSString*) valueOfProperty: (NSString*)property;

/** Same as -valueOfProperty:. Enables "[]" access in Xcode 4.4+ */
- (NSString*)objectForKeyedSubscript:(NSString*)key;

/** A shortcut to set the value of a property. A nil value deletes that property. */
- (void) setValue: (NSString*)value ofProperty: (NSString*)property;

/** Same as -setValue:ofProperty:. Enables "[]" access in Xcode 4.4+ */
- (void) setObject: (NSString*)value forKeyedSubscript:(NSString*)key;

/** Similar to -description, but also shows the properties and their values. */
@property (readonly) NSString* descriptionWithProperties;


@end
