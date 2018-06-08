//
//  BLIPFileResponse.m
//
//  Created by Matthew Nespor on 2/24/14.
//  Copyright (c) 2014 Nanonation. All rights reserved.
//

#import "BLIPFileRequest.h"
#import "BLIPFileResponse.h"
#import "Logging.h"
#import "BLIP_Internal.h"

#import "Test.h"
#import "ExceptionUtils.h"
// From Google Toolbox For Mac <http://code.google.com/p/google-toolbox-for-mac/>
#import "GTMNSData+zlib.h"

#import <CommonCrypto/CommonDigest.h>


@interface BLIPFileResponse ()
{
    BOOL _receivedMD5ctxInited;
    unsigned long long _totalBytesReceived;
    CC_MD5_CTX _receivedMD5ctx;
}
- (NSString*)mungedPath;

@end


@implementation BLIPFileResponse
{
    NSOutputStream* _stream;
 
    // BLIPMessage (Friend)
 
    // BLIPResponse (Friend)
}

- (void)dealloc
{
    // close the stream if it's still open
    [self->_stream close];
    self->_stream = nil;
    LogTo(BLIPVerbose,@"DEALLOC");
}

// As soon as properties are available, check for BodyIsFile. If true, write out data rec'd up to this point, then continue writing all
// future frames instead of building up an nsdata in memory.

#pragma mark - BLIPMessage overrides

// ============================================
//
// READ THIS.
//
// This section contains overridden BLIPMessage behavior. BLIPRequest and BLIPResponse both inherit from BLIPMessage.
// If you change something here, it's VERY LIKELY that you intend to make a corresponding change in BlipFileRequest too.
//
// ============================================

- (BOOL) _receivedFrameWithFlags: (BLIPMessageFlags)flags body: (NSData*)body
{
    Assert(!_isMine);
    Assert(_flags & kBLIP_MoreComing);
    
    BLIPMessageType frameType = (flags & kBLIP_TypeMask), curType = (_flags & kBLIP_TypeMask);
    if( frameType != curType )
    {
        Assert(curType==kBLIP_RPY && frameType==kBLIP_ERR && _mutableBody.length==0, @"Incoming frame's type %i doesn't match %@",frameType,self);
        _flags = (_flags & ~kBLIP_TypeMask) | frameType;
    }
    
    _totalBytesReceived += body.length;

    LogTo(BLIPVerbose,@"%@ rcvd bytes %llu-%llu", self, _totalBytesReceived-body.length, _totalBytesReceived);
    
    // Try to extract the properties if we haven't already
    if (!_properties)
    {
        if (_encodedBody)
            [_encodedBody appendData:body];
        else
            _encodedBody = [body mutableCopy];
        body = NULL;

        ssize_t usedLength;
        _properties = [BLIPProperties propertiesWithEncodedData:_encodedBody usedLength:&usedLength];
        if (_properties)
        {
            [_encodedBody replaceBytesInRange:NSMakeRange(0,usedLength) withBytes:NULL length:0];
            self.propertiesAvailable = YES;
            if (self.onPropertiesAvailable)
                self.onPropertiesAvailable(self.properties);
        }
        else
            return (usedLength == 0);
    }
    
    // at this point, properties are available... if there isn't a BodyIsFile property, we'd won't write to the file
    // on disk and instead, if we're not complete, simply keep doing what the super's implementation would have been doing
    BOOL useFileHandling = [self.properties[@"BodyIsFile"] boolValue];
    if (!useFileHandling)
    {
        if (body.length)
            [_encodedBody appendData:body];
    }
    else
    {
        // okay, the body is compressed, and we don't do that for files yet, log an error and return NO(pe)
        if (self.compressed)
        {
            LogTo(BLIP,@"%@: Compression is not yet supported for BLIPFileResponse", self);
            return NO;
        }
        
        // okay, the body is a file, but if we don't have a file path to store to, log an error and return NO(pe)
        if ([self.path length] == 0)
        {
            LogTo(BLIP,@"%@:_receivedFrameWithFlags: received a message with BodyIsFile=true, but local file path is nil or empty", self);
            return NO;
        }
        
        // so now we're into file data, let's make sure we're ready to generate a checksum
        if (!self->_receivedMD5ctxInited)
        {
            CC_MD5_Init(&self->_receivedMD5ctx);
            self->_receivedMD5ctxInited = YES;
        }
        
        // and that we have a file stream to write to
        if (self->_stream == nil)
        {
            self->_stream = [NSOutputStream outputStreamToFileAtPath:[self mungedPath] append:NO];
            [self->_stream open];
            if (self->_stream == nil)
            {
                LogTo(BLIP,@"%@:_receivedFrameWithFlags: could not open a file stream to path: '%@'", self, [self mungedPath]);
                return NO;
            }
        }
        
        // if we have data in _encodedBody, then we must have just finished parsing properties
        // and we need to write what's left to disk, we then null out _encodedData and _body as we aren't going to
        // need them any more
        if (_encodedBody != NULL)
        {
            if (_encodedBody.length > 0)
            {
                NSInteger result = [self->_stream write:[_encodedBody bytes] maxLength:_encodedBody.length];
                if (result < 0)
                {
                    LogTo(BLIP,@"%@: Encountered a problem writing to file %@: %@", self, self.path, self->_stream.streamError);
                    [self->_stream close];
                    return NO;
                }
                CC_MD5_Update(&self->_receivedMD5ctx, [_encodedBody bytes], (unsigned int)[_encodedBody length]);
            }
            _encodedBody = nil;
            _body = nil;
        }
        else
        {
            // if we didn't have data in _encodedBody, then this must be a subsequent frame and we can just
            // write the entire 'body' parameter's data itself to the file
            if (body.length > 0)
            {
                NSInteger result = [self->_stream write:[body bytes] maxLength:body.length];
                if (result < 0)
                {
                    LogTo(BLIP,@"%@: Encountered a problem writing to file %@: %@", self, self.path, self->_stream.streamError);
                    [self->_stream close];
                    return NO;
                }
                CC_MD5_Update(&self->_receivedMD5ctx, [body bytes], (unsigned int)[body length]);
            }
        }
    }
    
    // if there's no more data, then we are done, so clean up and finish
    if (!(flags & kBLIP_MoreComing))
    {
        // close the stream
        [self->_stream close];
        self->_stream = nil;

        // After last frame, decode the data:
        _flags &= ~kBLIP_MoreComing;
        if( ! _properties )
            return NO;
        
        if (!useFileHandling)
        {
            NSUInteger encodedLength = _encodedBody.length;
            if (self.compressed && (encodedLength > 0))
            {
                _body = [[NSData gtm_dataByInflatingData: _encodedBody] copy];
                if (!_body)
                    return NO;
                
                LogTo(BLIPVerbose,@"Uncompressed %@ from %lu bytes (%.1fx)", self, (unsigned long)encodedLength, _body.length/(double)encodedLength);
            }
            else
                _body = [_encodedBody copy];
            _encodedBody = nil;
        }
        else
        {
            // calculate the MD5 hash string
            unsigned char digest[CC_MD5_DIGEST_LENGTH];
            CC_MD5_Final(digest, &self->_receivedMD5ctx);
            self.receivedFileMD5hash = [NSString stringWithFormat: @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                                        digest[0], digest[1],
                                        digest[2], digest[3],
                                        digest[4], digest[5],
                                        digest[6], digest[7],
                                        digest[8], digest[9],
                                        digest[10], digest[11],
                                        digest[12], digest[13],
                                        digest[14], digest[15]];
            
            // move the file from the 'munged' path to the place the caller actually wanted it
            NSError* error = NULL;
            NSFileManager* fileManager = [[NSFileManager alloc] init];
            if ([fileManager fileExistsAtPath:self.path])
                [fileManager removeItemAtPath:self.path error:nil];
            if (![fileManager moveItemAtPath:[self mungedPath] toPath:self.path error:&error])
            {
                LogTo(BLIP,@"%@: Error moving temp file from %@ to %@: %@", self, [self mungedPath], self.path, error);
                return NO;
            }
        }
        
        if (!self.propertiesAvailable)
        {
            self.propertiesAvailable = YES;
            if (self.onPropertiesAvailable)
                self.onPropertiesAvailable(self.properties);
        }
        self.complete = YES;
    }

    return YES;
}

- (NSString*)mungedPath
{
    return [self.path stringByAppendingString:@".part"];
}

- (void)setComplete:(BOOL)complete
{
    [super setComplete:complete];
    if (complete && self.completionBlock)
    {
        self.completionBlock(self);
    }
}

@end
