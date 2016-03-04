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

#import <CommonCrypto/CommonDigest.h>

@interface BLIPResponse (Private)
- (BOOL)_receivedFrameWithFlags:(BLIPMessageFlags)flags body:(NSData*)body;
@end;

@interface BLIPFileResponse ()
{
    BOOL _receivedMD5ctxInited;
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
    // use the file implementation only if the body is a file
    if (!(self.propertiesAvailable && [self.properties[@"BodyIsFile"] boolValue]))
    {
        return [super _receivedFrameWithFlags:flags body:body];
    }

    if (self->_stream == nil)
    {
        if ([self.path length] == 0)
        {
            LogTo(BLIP,@"%@:_receivedFrameWithFlags: WARNING: Received a message with BodyIsFile=true, but local file path is nil or empty. Continuing with default BLIPMessage behavior", self);
            return [super _receivedFrameWithFlags:flags body:body];
        }
        else
        {
            if (!self->_receivedMD5ctxInited)
            {
                CC_MD5_Init(&self->_receivedMD5ctx);
                self->_receivedMD5ctxInited = YES;
            }
            
            self->_stream = [NSOutputStream outputStreamToFileAtPath:[self mungedPath] append:NO];
            [self->_stream open];
            // by the time this branch is reached, the properties have already been stripped from _encodedbody.
            [self->_stream write:[_encodedBody bytes] maxLength:_encodedBody.length];
            CC_MD5_Update(&self->_receivedMD5ctx, [_encodedBody bytes], (unsigned int)[_encodedBody length]);
        }
    }
    
    // If properties aren't available, continue with the base implementation.
    // When properties become available, if BodyIsFile, try to open an NSOutputStream
    // for URL. If that succeeds, write all the body we've received so far to the file, then
    // make all future writes to the file.
    //
    // If opening the stream fails, use the base implementation and log an error.
    BLIPMessageType frameType = (flags & kBLIP_TypeMask), curType = (_flags & kBLIP_TypeMask);
    if( frameType != curType ) {
        _flags = (_flags & ~kBLIP_TypeMask) | frameType;
    }
    
    if (self->_stream && (body.length > 0))
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
    
    if( ! (flags & kBLIP_MoreComing) ) {
        // After last frame, decode the data:
        _flags &= ~kBLIP_MoreComing;
        if( ! _properties )
            return NO;
        [self->_stream close];
        self->_stream = nil;
//        NSUInteger encodedLength = _encodedBody.length;
//        if( self.compressed && encodedLength>0 ) {
        if( self.compressed ) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString stringWithFormat:@"%@: Compression is not yet supported for BLIPFileResponse",
                                                   NSStringFromSelector(_cmd)]
                                         userInfo:nil];
            
//            _body = [[NSData gtm_dataByInflatingData: _encodedBody] copy];
//            if( ! _body )
//                return NO;
//            LogTo(BLIPVerbose,@"Uncompressed %@ from %lu bytes (%.1fx)", self, (unsigned long)encodedLength,
//                  _body.length/(double)encodedLength);
        } else {
            _body = [_encodedBody copy];
        }
        _encodedBody = nil;
        
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

        NSFileManager* fileManager = [[NSFileManager alloc] init];
        
        if ([fileManager fileExistsAtPath:self.path])
            [fileManager removeItemAtPath:self.path error:nil];
        
        NSError* error = NULL;
        if (![fileManager moveItemAtPath:[self mungedPath] toPath:self.path error:&error])
            LogTo(BLIP,@"%@: Error moving temp file from %@ to %@: %@", self, [self mungedPath], self.path, error);
        
        self.propertiesAvailable = self.complete = YES;
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
