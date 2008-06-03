#!/usr/bin/env python
# encoding: utf-8
"""
BLIP.py

Created by Jens Alfke on 2008-06-03.
Copyright (c) 2008 Jens Alfke. All rights reserved.
"""

import asynchat
import asyncore
from cStringIO import StringIO
import logging
import socket
import struct
import sys
import traceback
import unittest
import zlib


kFrameMagicNumber   = 0x9B34F205
kFrameHeaderFormat  = '!LLHH'
kFrameHeaderSize    = 12

kMsgFlag_TypeMask   = 0x000F
kMsgFlag_Compressed = 0x0010
kMsgFlag_Urgent     = 0x0020
kMsgFlag_NoReply    = 0x0040
kMsgFlag_MoreComing = 0x0080

kMsgType_Request    = 0
kMsgType_Response   = 1
kMsgType_Error      = 2


log = logging.getLogger('BLIP')
log.propagate = True

class MessageException(Exception):
    pass

class ConnectionException(Exception):
    pass


class Listener (asyncore.dispatcher):
    def __init__(self, port):
        asyncore.dispatcher.__init__(self)
        self.onConnected = None
        self.onRequest = None
        self.create_socket(socket.AF_INET, socket.SOCK_STREAM)
        self.bind( ('',port) )
        self.listen(5)
        log.info("Listening on port %u", port)
    
    def handle_accept( self ):
        client,address = self.accept()
        conn = Connection(address,client)
        conn.onRequest = self.onRequest
        if self.onConnected:
            self.onConnected(conn)


class Connection (asynchat.async_chat):
    def __init__( self, address, conn=None ):
        asynchat.async_chat.__init__(self,conn)
        self.address = address
        if conn:
            log.info("Accepted connection from %s",address)
        else:
            log.info("Opening connection to %s",address)
            self.create_socket(socket.AF_INET, socket.SOCK_STREAM)
            self.connect(address)
        self.onRequest = None
        self.pendingRequests = {}
        self.pendingResponses = {}
        self.outBox = []
        self.inMessage = None
        self.inNumRequests = 0
        self._endOfFrame()
    
    #def handle_error(self,x):
    #    log.error("Uncaught exception: %s",x)
    #    self.close()
    
    def _fatal(self, error):
        log.error("Fatal BLIP connection error: %s",error)
        self.close()
    
    
    ### SENDING:
    
    def _outQueueMessage(self, msg,isNew=True):
        n = self.outBox.length
        index = n
        if msg.urgent and n>1:
            while index > 0:
                otherMsg = self.outBox[index]
                if otherMsg.urgent:
                    if index<n:
                        index += 1
                    break
                elif isNew and otherMsg._bytesWritten==0:
                    break
                index -= 1
            else:
                index = 1
                    
        self.outBox.insert(index,msg)
        if isNew:
            log.info("Queuing outgoing message at index %i",index)
    
    def _sendNextFrame(self):
        n = len(self.outBox)
        if n > 0:
            msg = self.outBox.pop(0)
            frameSize = 4096
            if msg.urgent or n==1 or not self.outBox[0].urgent:
                frameSize *= 4
            if msg._sendNextFrame(self):
                self._outQueueMessage(msg,isNew=False)
    
    
    ### RECEIVING:
    
    def collect_incoming_data(self, data):
        if self.expectingHeader:
            if self.inHeader==None:
                self.inHeader = data
            else:
                self.inHeader += data
        else:
            self.inMessage._receivedData(data)
        
    def found_terminator(self):
        if self.expectingHeader:
            # Got a header:
            (magic, requestNo, flags, frameLen) = struct.unpack(kFrameHeaderFormat,self.inHeader)
            self.inHeader = None
            if magic!=kFrameMagicNumber: self._fatal("Incorrect frame magic number %x" %magic)
            if frameLen < kFrameHeaderSize: self._fatal("Invalid frame length %u" %frameLen)
            frameLen -= kFrameHeaderSize
            log.debug("Incoming frame: type=%i, number=%i, flags=%x, length=%i",
                        (flags&kMsgFlag_TypeMask),requestNo,flags,frameLen)
            self.inMessage = self._inMessageForFrame(requestNo,flags)
            
            if frameLen > 0:
                self.expectingHeader = False
                self.set_terminator(frameLen)
            else:
                self._endOfFrame()
                
        else:
            # Got the frame's payload:
            self._endOfFrame()
    
    def _inMessageForFrame(self, requestNo,flags):
        message = None
        msgType = flags & kMsgFlag_TypeMask
        if msgType==kMsgType_Request:
            message = self.pendingRequests.get(requestNo)
            if message==None and requestNo == self.inNumRequests+1:
                message = IncomingRequest(self,requestNo,flags)
                self.pendingRequests[requestNo] = message
                self.inNumRequests += 1
        elif msgType==kMsgType_Response or msgType==kMsgType_Error:
            message = self.pendingResponses.get(requestNo)
            
        if message:
            message._beginFrame(flags)
        else:
            log.warning("Ignoring unexpected frame with type %u, request #%u", msgType,requestNo)
        return message
    
    def _endOfFrame(self):
        msg = self.inMessage
        self.inMessage = None
        self.expectingHeader = True
        self.inHeader = None
        self.set_terminator(kFrameHeaderSize) # wait for binary header
        if msg:
            log.debug("End of frame of %s",msg)
            if not msg.moreComing:
                self._receivedMessage(msg)

    def _receivedMessage(self, msg):
        log.info("Received: %s",msg)
        # Remove from pending:
        if msg.isResponse:
            del self.pendingReplies[msg.requestNo]
        else:
            del self.pendingRequests[msg.requestNo]
        # Decode:
        try:
            msg._finished()
        except Exception, x:
            log.error("Exception parsing message: %s", traceback.format_exc())
            return
        # Dispatch:
        try:
            self.onRequest(msg)
        except Exception, x:
            log.error("Exception dispatching message: %s", traceback.format_exc())
            #FIX: Send an error reply

### MESSAGES:


class Message (object):
    def __init__(self, connection, properties=None, body=None):
        self.connection = connection
        self.properties = properties or {}
        self.body = body
    
    @property
    def flags(self):
        flags = kMsgType_Request
        if self.urgent:     flags |= kMsgFlag_Urgent
        if self.compressed: flags |= kMsgFlag_Compressed
        if self.noReply:    flags |= kMsgFlag_NoReply
        if self.moreComing: flags |= kMsgFlag_MoreComing
        return flags
    
    def __str__(self):
        s = "%s[#%i" %(type(self).__name__,self.requestNo)
        if self.urgent:     s += " URG"
        if self.compressed: s += " CMP"
        if self.noReply:    s += " NOR"
        if self.moreComing: s += " MOR"
        if self.body:       s += " %i bytes" %len(self.body)
        return s+"]"
    
    def __repr__(self):
        s = str(self)
        if len(self.properties): s += repr(self.properties)
        return s
        
    @property
    def isResponse(self):
        return False


class IncomingMessage (Message):
    def __init__(self, connection, requestNo, flags):
        super(IncomingMessage,self).__init__(connection)
        self.requestNo  = requestNo
        self.urgent     = (flags & kMsgFlag_Urgent) != 0 
        self.compressed = (flags & kMsgFlag_Compressed) != 0
        self.noReply    = (flags & kMsgFlag_NoReply) != 0
        self.moreComing = (flags & kMsgFlag_MoreComing) != 0
        self.frames     = []
    
    def _beginFrame(self, flags):
        if (flags & kMsgFlag_MoreComing)==0:
            self.moreComing = False

    def _receivedData(self, data):
        self.frames.append(data)
    
    def _finished(self):
        encoded = "".join(self.frames)
        self.frames = None
        
        # Decode the properties:
        if len(encoded) < 2: raise MessageException, "missing properties length"
        propSize = 2 + struct.unpack('!H',encoded[0:2])[0]
        if propSize>len(encoded): raise MessageException, "properties too long to fit"
        if propSize>2 and encoded[propSize-1] != '\000': raise MessageException, "properties are not nul-terminated"
        
        proplist = encoded[2:propSize-1].split('\000')
        encoded = encoded[propSize:]
        if len(proplist) & 1: raise MessageException, "odd number of property strings"
        for i in xrange(0,len(proplist),2):
            def expand(str):
                if len(str)==1:
                    str = IncomingMessage.__expandDict.get(str,str)
                return str
            self.properties[ expand(proplist[i])] = expand(proplist[i+1])
        
        # Decode the body:
        if self.compressed and len(encoded)>0:
            try:
                encoded = zlib.decompress(encoded,31)   # window size of 31 needed for gzip format
            except zlib.error:
                raise MessageException, sys.exc_info()[1]
        self.body = encoded
    
    __expandDict= {'\x01' : "Content-Type",
                   '\x02' : "Profile",
                   '\x03' : "application/octet-stream",
                   '\x04' : "text/plain; charset=UTF-8",
                   '\x05' : "text/xml",
                   '\x06' : "text/yaml",
                   '\x07' : "Channel",
                   '\x08' : "Error-Code",
                   '\x09' : "Error-Domain"}
        


class OutgoingMessage (Message):
    
    def send(self):
        out = StringIO()
        out.write("xx")         # placeholder for properties length (16 bits)
        for (key,value) in self.properties:
            def _writePropString(self, str):
                out.write(str)
                #FIX: Abbreviate
                out.write('\000')
            self._writePropString(key)
            self._writePropString(value)
        propsLen = out.tell()
        self.encoded = out.stringvalue()
        out.close()
        self.encoded[0:2] = struct.pack('!H',propsLen)
        
        body = self.body
        if self.compressed:
            body = zlib.compress(body,5)
        self.encoded += body
        
        self.bytesSent = 0
        self.connection._outQueueMessage(self)
    
    def _sendNextFrame(self, conn,maxLen):
        pos = self.bytesSent
        payload = self.encoded[pos:pos+maxLen]
        pos += len(payload)
        if pos >= len(self.encoded):
            self.moreComing = False

        conn.push( struct.pack(kFrameHeaderFormat, 
                               kFrameMagicNumber,
                               self.requestNo,
                               self.flags,
                               kFrameHeaderSize+len(payload)) )
        conn.push( payload )
        
        self.bytesSent = pos


class Request (Message):
    pass

class Response (Message):
    @property
    def isResponse(self):
        return True

    @property
    def flags(self):
        flags = super(Response,self).flags() ^ kMsgType_Request
        flags ^= kMsgType_Response
        return flags



class IncomingRequest (IncomingMessage, Request):
    pass

class OutgoingRequest (OutgoingMessage, Request):
    pass

class IncomingResponse (IncomingMessage, Response):
    pass

class OutgoingResponse (OutgoingMessage, Response):
    pass


### UNIT TESTS:


class BLIPTests(unittest.TestCase):
    def setUp(self):
        listener = Listener(46353)
        listener.onRequest = lambda req: logging.info("Got request!: %r",req)
    
    def testListener(self):
        logging.info("Waiting...")
        asyncore.loop()

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    unittest.main()