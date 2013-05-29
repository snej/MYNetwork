//
//  BLIPWebSocketTest.m
//  MYNetwork
//
//  Created by Jens Alfke on 4/1/13.
//
//

#import "BLIPWebSocket.h"
#import "BLIP.h"

#import "IPAddress.h"
#import "Target.h"
#import "CollectionUtils.h"
#import "Logging.h"
#import "Test.h"


#define kSendInterval               0.5
#define kNBatchedMessages           20
#define kUseCompression             YES
#define kUrgentEvery                4
#define kListenerCloseAfter         50
#define kClientAcceptCloseRequest   YES



@interface BLIPWebSocketTester : NSObject <BLIPWebSocketDelegate>
@end


@implementation BLIPWebSocketTester
{
    BLIPWebSocket *_conn;
    NSMutableDictionary *_pending;
}

- (id) init
{
    self = [super init];
    if (self != nil) {
        Log(@"** INIT %@",self);
        _pending = [[NSMutableDictionary alloc] init];
        _conn = [[BLIPWebSocket alloc] initWithURL: [NSURL URLWithString: @"ws://localhost:12345/test"]];
        if( ! _conn ) {
            return nil;
        }
        _conn.delegate = self;
        Log(@"** Opening connection...");
        [_conn open];
    }
    return self;
}

- (void) dealloc
{
    Log(@"** %@ closing",self);
    [_conn close];
}

- (void) sendAMessage
{
    if(_pending.count<100) {
        Log(@"** Sending a message that will fail to be handled...");
        BLIPRequest *q = [_conn requestWithBody: nil
                                     properties: $dict({@"Profile", @"BLIPTest/DontHandleMe"},
                                                       {@"User-Agent", @"BLIPConnectionTester"},
                                                       {@"Date", [[NSDate date] description]})];
        BLIPResponse *response = [q send];
        Assert(response);
        Assert(q.number>0);
        Assert(response.number==q.number);
        _pending[$object(q.number)] = [NSNull null];
        response.onComplete = $target(self,responseArrived:);
        
        Log(@"** Sending another %i messages...", kNBatchedMessages);
        for( int i=0; i<kNBatchedMessages; i++ ) {
            size_t size = random() % 32768;
            NSMutableData *body = [NSMutableData dataWithLength: size];
            UInt8 *bytes = body.mutableBytes;
            for( size_t i=0; i<size; i++ )
                bytes[i] = i % 256;
            
            q = [_conn requestWithBody: body
                             properties: $dict({@"Profile", @"BLIPTest/EchoData"},
                                               {@"Content-Type", @"application/octet-stream"},
                                               {@"User-Agent", @"BLIPConnectionTester"},
                                               {@"Date", [[NSDate date] description]},
                                               {@"Size",$sprintf(@"%zu",size)})];
            Assert(q);
            if( kUseCompression && (random()%2==1) )
                q.compressed = YES;
            if( random()%16 > 12 )
                q.urgent = YES;
            BLIPResponse *response = [q send];
            Assert(response);
            Assert(q.number>0);
            Assert(response.number==q.number);
            _pending[$object(q.number)] = $object(size);
            response.onComplete = $target(self,responseArrived:);
        }
    } else {
        Warn(@"There are %lu pending messages; waiting for the listener to catch up...",(unsigned long)_pending.count);
    }
    [self performSelector: @selector(sendAMessage) withObject: nil afterDelay: kSendInterval];
}

- (void) responseArrived: (BLIPResponse*)response
{
    Log(@"********** called responseArrived: %@",response);
}

- (void)blipWebSocketDidOpen:(BLIPWebSocket*)webSocket;
{
    Log(@"** %@ didOpen", webSocket);
    [self sendAMessage];
}

- (void)blipWebSocket: (BLIPWebSocket*)webSocket didFailWithError:(NSError *)error;
{
    Warn(@"** %@ failedWithError: %@",webSocket,error);
    CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void)blipWebSocket: (BLIPWebSocket*)webSocket
     didCloseWithCode:(NSInteger)code
               reason:(NSString *)reason
             wasClean:(BOOL)wasClean;
{
    Warn(@"** %@ didCloseWithCode: %ld reason: '%@', clean:%d", webSocket, (long)code, reason, wasClean);
    _conn = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget: self];
    CFRunLoopStop(CFRunLoopGetCurrent());
}

- (BOOL) blipWebSocket: (BLIPWebSocket*)webSocket receivedRequest: (BLIPRequest*)request;
{
    Log(@"***** %@ received %@",webSocket,request);
    [request respondWithData: request.body contentType: request.contentType];
    return YES;
}

- (void) blipWebSocket: (BLIPWebSocket*)webSocket receivedResponse: (BLIPResponse*)response;
{
    Log(@"********** %@ received %@",webSocket,response);
    id sizeObj = _pending[$object(response.number)];
    Assert(sizeObj);
    
    if (sizeObj == [NSNull null]) {
        AssertEqual(response.error.domain, BLIPErrorDomain);
        AssertEq(response.error.code, kBLIPError_NotFound);
    } else {
        if( response.error )
            Warn(@"Got error response: %@",response.error);
        else {
            NSData *body = response.body;
            size_t size = body.length;
            Assert(size<32768);
            const UInt8 *bytes = body.bytes;
            for( size_t i=0; i<size; i++ )
                AssertEq(bytes[i],i % 256);
            AssertEq(size,[sizeObj unsignedIntValue]);
        }
    }
    [_pending removeObjectForKey: $object(response.number)];
    Log(@"Now %lu replies pending", (unsigned long)_pending.count);
}


@end


TestCase(BLIPWebSocket) {
    BLIPWebSocketTester *tester = [[BLIPWebSocketTester alloc] init];
    CAssert(tester);
    
    [[NSRunLoop currentRunLoop] run];
    
    Log(@"** Runloop stopped");
}

