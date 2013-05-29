//
//  BLIPHTTPTest.m
//  MYNetwork
//
//  Created by Jens Alfke on 4/1/13.
//
//

#import "BLIPWebSocket.h"
#import "BLIPRequest+HTTP.h"
#import "BLIPHTTPProtocol.h"

#import "Target.h"
#import "CollectionUtils.h"
#import "Logging.h"
#import "Test.h"


#define kSendInterval               0.5
#define kNBatchedMessages           10
#define kUseCompression             YES
#define kUrgentEvery                4
#define kListenerCloseAfter         50
#define kClientAcceptCloseRequest   YES

#define kWebSocketURL @"http://localhost:12345/test"
#define kTestURL @"http://bliptest/"



@interface BLIPHTTPTester : NSObject <NSURLConnectionDelegate, NSURLConnectionDataDelegate>
@end


@implementation BLIPHTTPTester
{
    NSURLConnection *_conn;
    NSMutableDictionary *_pending;
}

- (id) init
{
    self = [super init];
    if (self != nil) {
        Log(@"** INIT %@",self);
        _pending = [[NSMutableDictionary alloc] init];
        [BLIPHTTPProtocol registerWebSocketURL: [NSURL URLWithString: kWebSocketURL]
                                        forURL: [NSURL URLWithString: kTestURL]];
        [self sendAMessage];
    }
    return self;
}

- (void) dealloc
{
    Log(@"** %@ closing",self);
}

- (void) sendAMessage
{
    if(_pending.count<100) {
        Log(@"** Sending a message that will fail to be handled...");
                
        Log(@"** Sending another %i messages...", kNBatchedMessages);
        for( int i=0; i<kNBatchedMessages; i++ ) {
            size_t size = random() % 32768;
            NSMutableData *body = [NSMutableData dataWithLength: size];
            UInt8 *bytes = body.mutableBytes;
            for( size_t i=0; i<size; i++ )
                bytes[i] = i % 256;

            Log(@"**     Sending %zu-byte message", size);
            NSMutableURLRequest* q = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: kTestURL "test"]];
            [q setValue: @"application/octet-stream" forHTTPHeaderField: @"Content-Type"];
            q.HTTPBody = body;
            NSURLConnection* urlConn = [NSURLConnection connectionWithRequest: q delegate: self];
            Assert(urlConn);

            _pending[[NSValue valueWithPointer: (__bridge void*)urlConn]] = $object(size);
        }
    } else {
        Warn(@"There are %lu pending messages; waiting for the listener to catch up...",(unsigned long)_pending.count);
    }
    [self performSelector: @selector(sendAMessage) withObject: nil afterDelay: kSendInterval];
}

- (void) connection: (NSURLConnection*)conn didReceiveResponse:(NSURLResponse *)response {
    Log(@"********** %@ received %@",conn,response);
    NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
    AssertEq(httpResponse.statusCode, 201);
}

- (void) connection: (NSURLConnection*)conn didReceiveData: (NSData*)body {
    Log(@"********** %@ received %u-byte body",conn,(unsigned)body.length);
    id key = [NSValue valueWithPointer: (__bridge void*)conn];
    Assert(_pending[key] != nil);
    size_t expectedSize = [_pending[key] intValue];
    size_t size = body.length;
    Assert(size<32768);
    AssertEq(size, expectedSize);
    const UInt8 *bytes = body.bytes;
    for( size_t i=0; i<size; i++ )
        AssertEq(bytes[i],i % 256);
}

- (void) removePending: (NSURLConnection*)conn {
    id key = [NSValue valueWithPointer: (__bridge void*)conn];
    Assert(_pending[key] != nil);
    [_pending removeObjectForKey: key];
    Log(@"Now %lu replies pending", (unsigned long)_pending.count);
}

- (void) connection: (NSURLConnection*)conn didFailWithError:(NSError *)error {
    Log(@"********** %@ failed: %@",conn, error);
    [self removePending: conn];
}

- (void) connectionDidFinishLoading:(NSURLConnection *)conn {
    Log(@"********** %@ finished",conn);
    [self removePending: conn];
}



@end


TestCase(BLIPHTTPConnection) {
    BLIPHTTPTester *tester = [[BLIPHTTPTester alloc] init];
    CAssert(tester);
    
    [[NSRunLoop currentRunLoop] run];
    
    Log(@"** Runloop stopped");
}

