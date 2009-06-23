# asynchatPong
# Listener using asynchat
# Not related to BLIP - just to aid in my understanding of what's going on
# Sends "Pong" when it gets "Ping"

import sys
import traceback
import socket
import asyncore
import asynchat

class asynchatPongListener(asyncore.dispatcher):
    def __init__(self, port):
        asyncore.dispatcher.__init__(self)
        self.create_socket(socket.AF_INET, socket.SOCK_STREAM)
        self.bind( ('', port) )
        self.listen(2)
        self.shouldAccept = True
    
    def handle_accept(self):
        if self.shouldAccept:
            sock, addr = self.accept()
            self.conn = asynchatPong(sock, self)
            self.shouldAccept = False
    
    def handle_error(self):
        (typ,val,trace) = sys.exc_info()
        print "Listener caught: %s %s\n%s" % (typ,val,traceback.format_exc())
        self.close()
    
    def handle_close(self):
        print "Listener got close"
        asyncore.dispatcher.handle_close(self)

class asynchatPong(asynchat.async_chat):
    def __init__(self, socket, listener):
        asynchat.async_chat.__init__(self, socket)
        self._listener = listener
        self.set_terminator("Ping")
    
    def collect_incoming_data(self, data):
        """called when arbitrary amount of data arrives. we just eat it"""
        pass
    
    def found_terminator(self):
        """called when the terminator we set is found"""
        print "Found 'Ping'"
        self.push("Pong")
        print "Sent 'Pong'"
    
    def handle_close(self):
        print "Closed; closing listener"
        self._listener.close()
        asynchat.async_chat.handle_close(self)
    

if __name__ == '__main__':
    pong = asynchatPongListener(1337)
    asyncore.loop()
