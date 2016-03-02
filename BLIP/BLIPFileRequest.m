//
//  BLIPFileRequest.m
//
//  Created by Matthew Nespor on 2/24/14.
//  Copyright (c) 2014 Nanonation. All rights reserved.
//

#import "BLIPFileRequest.h"
#import "BLIPFileResponse.h"
#import "BLIPWriter.h"
#import "Logging.h"
#import "BLIP_Internal.h"

@interface BLIPFileRequest ()
{
    NSInputStream* _stream;
    
    // BLIPMessage (Friend)
    
    // BLIPRequest (Friend)
    BLIPResponse* _response;
    NSData* _encodedProperties;
}

@property (copy, nonatomic) void (^completionBlock)(BLIPResponse* response);

@end


@implementation BLIPFileRequest

- (Class)responseClass
{
    return [BLIPFileResponse class];
}

+ (BLIPFileRequest*)pushRequestWithBodyFilePath:(NSString *)filePath properties:(NSDictionary *)properties completionBlock:(void (^)(BLIPResponse *))completionBlock
{
    return [[BLIPFileRequest alloc] _initWithConnection:nil
                                                properties:properties
                                                    isMine:YES
                                                     flags:kBLIP_MSG
                                                    number:0
                                               outFilePath:filePath
                                                inFilePath:nil
                                                      hash:nil
                                           completionBlock:completionBlock];
}

+ (BLIPFileRequest*)pullRequestWithProperties:(NSDictionary *)properties
                                 destinationPath:(NSString *)destinationPath
                                    expectedHash:(NSString *)hash
                                 completionBlock:(void (^)(BLIPResponse *))completionBlock
{
    return [[BLIPFileRequest alloc] _initWithConnection:nil
                                                properties:properties
                                                    isMine:YES
                                                     flags:kBLIP_MSG
                                                    number:0
                                               outFilePath:nil
                                                inFilePath:destinationPath
                                                      hash:hash
                                           completionBlock:completionBlock];
}

#pragma mark - BLIPRequest overrides

- (id)mutableCopyWithZone:(NSZone *)zone
{
    BLIPRequest *copy = [[self class] requestWithBody: self.body
                                           properties: self.properties.allProperties];
    if ([copy isKindOfClass:[BLIPFileRequest class]])
    {
        BLIPFileRequest* r = (BLIPFileRequest*)copy;
        r.expectedHash = self.expectedHash;
        r.outFilePath = self.outFilePath;
        r.inFilePath = self.inFilePath;
    }
    copy.compressed = self.compressed;
    copy.urgent = self.urgent;
    copy.noReply = self.noReply;
    return copy;
}

- (BLIPResponse*)send
{
    BLIPResponse* response = [super send];
    if (self.completionBlock && [response isKindOfClass:[BLIPFileResponse class]])
    {
        BLIPFileResponse* r = (BLIPFileResponse*)response;
        r.completionBlock = self.completionBlock;
    }
    return response;
}

- (BLIPResponse*) response
{
    if( ! self->_response && ! self.noReply )
    {
        [self willChangeValueForKey:@"repliedTo"];
        _response = [[[self responseClass] alloc] _initWithRequest: self];
        if ([_response isKindOfClass:[BLIPFileResponse class]])
        {
            BLIPFileResponse* resp = (BLIPFileResponse*)_response;
            resp.path = self.inFilePath;
            resp.expectedHash = self.expectedHash;
        }
        [self didChangeValueForKey:@"repliedTo"];
    }
    return _response;
}

#pragma mark - BLIPMessage overrides

// ============================================
//
// READ THIS.
//
// This section contains overridden BLIPMessage behavior. BLIPRequest and BLIPResponse both inherit from BLIPMessage.
// If you change something here, it's VERY LIKELY that you intend to make a corresponding change in BLIPFileResponse too.
//
// ============================================


// override everything that touches _encodedBody

- (void) _encode
{
    if (!(self.propertiesAvailable && [self.properties[@"BodyIsFile"] boolValue]))
    {
        [super _encode];
        return;
    }
    
    _isMutable = NO;
    
    BLIPProperties *oldProps = _properties;
    _properties = [oldProps copy];
    
    _encodedProperties = [_properties.encodedData mutableCopy];
    
    [self->_stream close];
    self->_stream = [NSInputStream inputStreamWithURL:[NSURL URLWithString:self->_outFilePath]];
    
    if (self.compressed)
    {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:[NSString stringWithFormat:@"%@: Compression is not yet supported for BLIPFileRequest",
                                               NSStringFromSelector(_cmd)]
                                     userInfo:nil];
    }
}

- (id) _initWithConnection: (BLIPConnection*)connection
                properties: (NSDictionary*)properties
                    isMine: (BOOL)isMine
                     flags: (BLIPMessageFlags)flags
                    number: (UInt32)msgNo
               outFilePath: (NSString*)outPath
                inFilePath: (NSString*)inPath
                      hash: (NSString*)hash
           completionBlock: (void (^)(BLIPResponse *))completionBlock
{
    self = [super init];
    if (self != nil) {
        _connection = connection;
        _isMine = isMine;
        _flags = flags;
        _number = msgNo;
        if( isMine ) {
            _isMutable = YES;
            _properties = [[BLIPMutableProperties alloc] init];
            _propertiesAvailable = YES;
            _complete = YES;
            _encodedProperties = nil;
            _outFilePath = outPath;
            _inFilePath = inPath;
            _expectedHash = hash;
            _completionBlock = completionBlock;
            if (properties)
            {
                [self.mutableProperties setAllProperties:properties];
            }
        }
        LogTo(BLIPVerbose,@"INIT %@",self);
    }
    return self;
}

- (BOOL) _writeFrameTo: (BLIPWriter*)writer maxSize: (UInt16)maxSize
{
    // use the file implementation only if the body is a file
    if (!(self.propertiesAvailable && [self.properties[@"BodyIsFile"] boolValue]))
    {
        return [super _writeFrameTo:writer maxSize:maxSize];
    }

    if( _bytesWritten==0 )
        LogTo(BLIP,@"Now sending %@",self);
    if (![_stream hasBytesAvailable])
    {
        [_stream close];
        _stream = nil;
        return NO;
    }
    
    ssize_t lengthToWrite = 0; //_encodedBody.length - _bytesWritten;
                               //    if( lengthToWrite <= 0 && _bytesWritten > 0 )
                               //        return NO; // done
    maxSize -= sizeof(BLIPFrameHeader);
    UInt16 flags = _flags;
    lengthToWrite += sizeof(BLIPFrameHeader);

    @autoreleasepool {
        NSMutableData* dataToWrite;
        if (_encodedProperties)
        {
            dataToWrite = [_encodedProperties mutableCopy];
            _encodedProperties = nil;
        }
        else
        {
            dataToWrite = [NSMutableData data];
        }
        
        lengthToWrite += [dataToWrite length];
        maxSize -= [dataToWrite length];
        
        uint8_t buf[maxSize];
        NSInteger readResult = [_stream read:buf maxLength:maxSize];
        if (readResult == 0)
        {
            // at this point, maxSize has been subtracted from twice - once the frame header size, and once the property size (if needed)
            [dataToWrite appendBytes:buf length:maxSize];
            lengthToWrite += maxSize;
            flags |= kBLIP_MoreComing;
            LogTo(BLIPVerbose,@"%@ pushing frame", self);
        }
        else if (readResult > 0)
        {
            // Job's done! http://www.youtube.com/watch?v=5r06heQ5HsI
            [_stream close];
            _stream = nil;
            [dataToWrite appendBytes:buf length:readResult];
            lengthToWrite += readResult; // if readResult > 0, readResult is the number of bytes that were actually read
            flags &= ~kBLIP_MoreComing;
            LogTo(BLIPVerbose,@"%@ pushing frame (finished)", self);
        }
        else if (readResult < 0)
        {
            LogTo(BLIPVerbose,@"%@ failed pushing frame. [NSInputStream read:maxLength] returned %ld: %@", self, (long)readResult, _stream.streamError);
            [_stream close];
            return NO;
        }
        
        // First write the frame header:
        BLIPFrameHeader header = {  NSSwapHostIntToBig(kBLIPFrameHeaderMagicNumber),
            NSSwapHostIntToBig(_number),
            NSSwapHostShortToBig(flags),
            NSSwapHostShortToBig(sizeof(BLIPFrameHeader) + lengthToWrite) };
        
        [writer writeData: [NSData dataWithBytes: &header length: sizeof(header)]];
        
        // Then write the body:
        if( lengthToWrite > 0 ) {
            [writer writeData: dataToWrite];
            //        [writer writeData: [NSData dataWithBytes: (UInt8*)_encodedBody.bytes + _bytesWritten
            //                                          length: lengthToWrite]];
            _bytesWritten += lengthToWrite;
        }
    }
    return (flags & kBLIP_MoreComing) != 0;
}

@end
