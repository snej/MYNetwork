//
//  BLIPFrameWriter.h
//  MYNetwork
//
//  Created by Jens Alfke on 5/18/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

@class BLIPRequest, BLIPResponse, BLIPMessage;


/** INTERNAL class that sends BLIP frames over the socket. */
@interface BLIPWriter : TCPWriter

- (BOOL) sendRequest: (BLIPRequest*)request response: (BLIPResponse*)response;
- (BOOL) sendMessage: (BLIPMessage*)message;

@property (readonly) UInt32 numRequestsSent;

@end
