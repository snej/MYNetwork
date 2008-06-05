#!/usr/bin/env python
# encoding: utf-8
"""
BLIPConnectionTest.py

Created by Jens Alfke on 2008-06-04.
This source file is test/example code, and is in the public domain.
"""

from BLIP import Connection, OutgoingRequest, kOpening

import asyncore
from cStringIO import StringIO
from datetime import datetime
import logging
import random
import unittest


kSendInterval = 2.0

def randbool():
    return random.randint(0,1) == 1


class BLIPConnectionTest(unittest.TestCase):

    def setUp(self):
        self.connection = Connection( ('localhost',46353) )
   
    def sendRequest(self):
        size = random.randint(0,32767)
        io = StringIO()
        for i in xrange(0,size):
            io.write( chr(i % 256) )
        body = io.getvalue()
        io.close
    
        req = OutgoingRequest(self.connection, body,{'Content-Type': 'application/octet-stream',
                                                     'User-Agent':  'PyBLIP',
                                                     'Date': datetime.now(),
                                                     'Size': size})
        req.compressed = randbool()
        req.urgent     = randbool()
        req.response.onComplete = self.gotResponse
        return req.send()
    
    def gotResponse(self, response):
        logging.info("Got response!: %s",response)
        request = response.request
        assert response.body == request.body

    def testClient(self):
        lastReqTime = None
        nRequests = 0
        while nRequests < 10:
            asyncore.loop(timeout=kSendInterval,count=1)
            
            now = datetime.now()
            if self.connection.status!=kOpening and not lastReqTime or (now-lastReqTime).seconds >= kSendInterval:
                lastReqTime = now
                if not self.sendRequest():
                    logging.warn("Couldn't send request (connection is probably closed)")
                    break;
                nRequests += 1
    
    def tearDown(self):
        self.connection.close()

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    unittest.main()
