# asynchatPing
# Uses asynchat
# Not related to BLIP - just to aid in my understanding of what's going on
# Sends "Ping", waits for "Pong"

import socket
import asyncore
import asynchat

kNumPings = 10

class asynchatPing(asynchat.async_chat):
    def __init__(self, address):
        asynchat.async_chat.__init__(self)
        self.create_socket(socket.AF_INET, socket.SOCK_STREAM)
        self.connect(address)
        self.set_terminator("Pong")
        self.pingsSent = self.pongsGot = 0
        self.donePing = self.donePong = False
    
    def handle_connect(self):
        print "Connected"
    
    def handle_close(self):
        print "Closed"
        asynchat.async_chat.handle_close(self)
    
    def collect_incoming_data(self, data):
        """discard data"""
        pass
    
    def found_terminator(self):
        """when we get a Pong"""
        print "Received 'Pong'"
        self.pongsGot += 1
        if self.pongsGot == kNumPings:
            print "Done ponging"
            self.donePong = True
            self.close_when_done()
    
    def ping(self):
        if not self.donePing:
            self.push("Ping")
            print "Sent 'Ping'"
            self.pingsSent += 1
            if self.pingsSent == kNumPings:
                print "Done pinging"
                self.donePing = True
    
    def run(self):
        timeout = 0
        while not self.donePing:
            self.ping()
            asyncore.loop(timeout=timeout, count=1)
        asyncore.loop()
        print "Done!"

if __name__ == '__main__':
    ping = asynchatPing( ('localhost', 1337) )
    ping.run()
