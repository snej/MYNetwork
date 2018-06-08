//
//  TCPStream.m
//  MYNetwork
//
//  Created by Jens Alfke on 5/10/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import "TCPStream.h"
#import "TCP_Internal.h"
#import "IPAddress.h"

#import "Logging.h"
#import "Test.h"


#if !TARGET_OS_IPHONE
// You can't do client-side SSL auth using CFStream without this constant,
// but it was accidentally not declared in a public header.
// Unfortunately you can't use this on iPhone without Apple rejecting your app
// for using "private API". :-(
extern const CFStringRef _kCFStreamPropertySSLClientSideAuthentication; // in CFNetwork
#endif

static NSError* fixStreamError( NSError *error );


@implementation TCPStream


- (id) initWithConnection: (TCPConnection*)conn stream: (NSStream*)stream
{
    self = [super init];
    if (self != nil) {
        _conn = conn;
        _stream = stream;
        _stream.delegate = self;
        [_stream scheduleInRunLoop: [NSRunLoop currentRunLoop] forMode: NSRunLoopCommonModes];
        LogTo(TCPVerbose,@"%@ initialized; status=%li", self, (long)_stream.streamStatus);
    }
    return self;
}


- (void) dealloc
{
    LogTo(TCP,@"DEALLOC %@",self);
    if( _stream )
        [self disconnect];
}


- (id) propertyForKey: (CFStringRef)cfStreamProperty
{
    return [_stream propertyForKey: (__bridge NSString*)cfStreamProperty];
}

- (void) setProperty: (id)value forKey: (CFStringRef)cfStreamProperty
{
    if( ! [_stream setProperty: value forKey: (__bridge NSString*)cfStreamProperty] )
        Warn(@"Failed to set property %@ on %@",cfStreamProperty,self);
}


- (IPAddress*) peerAddress
{
    const CFSocketNativeHandle *socketPtr = [[self propertyForKey: kCFStreamPropertySocketNativeHandle] bytes];
    return socketPtr ?[IPAddress addressOfSocket: *socketPtr] :nil;
}


#pragma mark -
#pragma mark SSL:


- (NSString*) securityLevel                 {return [_stream propertyForKey: NSStreamSocketSecurityLevelKey];}

- (NSDictionary*) SSLProperties             {return [self propertyForKey: kCFStreamPropertySSLSettings];}

- (void) setSSLProperties: (NSDictionary*)p
{
    LogTo(TCPVerbose,@"%@ SSL settings := %@",self,p);
    [self setProperty: p forKey: kCFStreamPropertySSLSettings];
    
#if !TARGET_OS_IPHONE
    id clientAuth = p[kTCPPropertySSLClientSideAuthentication];
    if( clientAuth )
        [self setProperty: clientAuth forKey: _kCFStreamPropertySSLClientSideAuthentication];
#endif
}

- (NSArray*) peerSSLCerts
{
    Assert(self.isOpen);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [self propertyForKey: kCFStreamPropertySSLPeerCertificates];
#pragma clang diagnostic pop
}


#pragma mark -
#pragma mark OPENING/CLOSING:


- (void) open
{
    Assert(_stream);
    AssertEq(_stream.streamStatus,(NSStreamStatus)NSStreamStatusNotOpen);
    LogTo(TCP,@"Opening %@",self);
    [_stream open];
}


- (void) disconnect
{
    if( _stream ) {
        LogTo(TCP,@"Disconnect %@",self);
        _stream.delegate = nil;
        [_stream close];
        _stream = nil;
    }
    if( _conn ) {
        [_conn _streamDisconnected: self];
//      _conn = nil; // this was line was the source of a strange sporadic console message/crash... I have yet to figure out exactly why, but commenting this line out doesn't seem to cause a leak or crash
    }
}


- (BOOL) close
{
    if( ! _shouldClose ) {
        _shouldClose = YES;
        LogTo(TCP,@"Request to close %@",self);
    }
    if( self.isBusy ) {
        return NO;
    } else {
        MYDeferDealloc(self);  // don't let me be dealloced during this
        [_conn _streamCanClose: self];
        return YES;
    }
}

- (void) _unclose
{
    _shouldClose = NO;
}


- (BOOL) isOpen
{
    NSStreamStatus status = _stream.streamStatus;
    return status >= NSStreamStatusOpen && status < NSStreamStatusAtEnd;
}

- (BOOL) isBusy
{
    return NO;  // abstract
}

- (BOOL) isActive
{
    return !_shouldClose || self.isBusy;
}


- (void) _opened
{
    [_conn _streamOpened: self];
}

- (void) _canRead
{
    // abstract
}

- (void) _canWrite
{
    // abstract
}

- (void) _gotEOF
{
    [_conn _streamGotEOF: self];
}

- (BOOL) _gotError: (NSError*)error
{
    [_conn _stream: self gotError: fixStreamError(error)];
    return NO;
}

- (BOOL) _gotError
{
    NSError *error = _stream.streamError;
    if( ! error )
        error = [NSError errorWithDomain: NSPOSIXErrorDomain code: EIO userInfo: nil]; //fallback
    return [self _gotError: error];
}


- (void) stream: (NSStream*)stream handleEvent: (NSStreamEvent)streamEvent 
{
    MYDeferDealloc(self);  // don't let me be dealloced during this
    switch(streamEvent) {
        case NSStreamEventOpenCompleted:
            LogTo(TCPVerbose,@"%@ opened",self);
            [self _opened];
            break;
        case NSStreamEventHasBytesAvailable:
            if( ! [_conn _streamPeerCertAvailable: self] )
                return;
            LogTo(TCPVerbose,@"%@ can read",self);
            [self _canRead];
            break;
        case NSStreamEventHasSpaceAvailable:
            if( ! [_conn _streamPeerCertAvailable: self] )
                return;
            LogTo(TCPVerbose,@"%@ can write",self);
            [self _canWrite];
            break;
        case NSStreamEventErrorOccurred:
            LogTo(TCPVerbose,@"%@ got error",self);
            [self _gotError];
            break;
        case NSStreamEventEndEncountered:
            LogTo(TCPVerbose,@"%@ got EOF",self);
            [self _gotEOF];
            break;
        default:
            Warn(@"%@: unknown NSStreamEvent %u",self,(unsigned)streamEvent);
            break;
    }
    
    // If I was previously asked to close, try again in case I'm no longer busy
    if( _shouldClose )
        [self close];
}


@end




@implementation TCPReader


- (TCPWriter*) writer
{
    return _conn.writer;
}

- (NSInteger) read: (void*)dst maxLength: (NSUInteger)maxLength
{
    NSInteger bytesRead = [(NSInputStream*)_stream read:dst maxLength: maxLength];
    if( bytesRead < 0 )
        [self _gotError];
    return bytesRead;
}


@end




static NSError* fixStreamError( NSError *error )
{
    // NSStream incorrectly returns SSL errors without the correct error domain:
    if( $equal(error.domain,@"NSUnknownErrorDomain") ) {
        NSInteger code = error.code;
        if( -9899 <= code && code <= -9800 ) {
            NSMutableDictionary *userInfo = error.userInfo.mutableCopy;
            if( ! userInfo[NSLocalizedFailureReasonErrorKey] ) {
                // look up error message:
                NSBundle *secBundle = [NSBundle bundleWithPath: @"/System/Library/Frameworks/Security.framework"];
                NSString *message = [secBundle localizedStringForKey: $sprintf(@"%li",(long)code)
                                                               value: nil
                                                               table: @"SecErrorMessages"];
                if( message ) {
                    if( ! userInfo ) userInfo = $mdict();
                    userInfo[NSLocalizedFailureReasonErrorKey] = message;
                }
            }
            error = [NSError errorWithDomain: NSStreamSocketSSLErrorDomain
                                        code: code userInfo: userInfo];
        } else
            Warn(@"NSStream returned error with unknown domain: %@",error);
    }
    return error;
}

/*
 Copyright (c) 2008, Jens Alfke <jens@mooseyard.com>. All rights reserved.
 
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
