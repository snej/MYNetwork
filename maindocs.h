//
//  maindocs.h
//  MYNetwork
//
//  Created by Jens Alfke on 5/24/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//
// This file just contains the Doxygen comments that generate the main (index.html) page content.


/*! \mainpage MYNetwork: Mooseyard Networking library, including BLIP protocol implementation. 
 
\section intro_sec Introduction
 
    MYNetwork is a set of Objective-C networking classes for Cocoa applications on Mac OS X.
    It consists of:
    <ul>
    <li>Networking utility classes (presently only IPAddress);
    <li>A generic TCP client/server implementation,
        useful for implementing your own network protocols; (see TCPListener and TCPConnection)
    <li>An implementation of BLIP, a lightweight network protocol I've invented as an easy way
        to send request and response messages between peers. (see BLIPListener, BLIPConnection, BLIPRequest, etc.)
    </ul>
 
    MYNetwork is released under a BSD license, which means you can freely use it in open-source
    or commercial projects, provided you give credit in your documentation or About box.

\section blipdesc What's BLIP?
 
BLIP is a message-oriented network protocol that lets the two peers on either end of a TCP socket send request and response messages to each other. It's a generic protocol, in that the requests and responses can contain any kind of data you like. 
 
BLIP was inspired by <a
href="http://beepcore.org">BEEP</a> (in fact BLIP stands for "BEEP-LIke Protocol") but is
deliberately simpler and somewhat more limited. That translates to a smaller and cleaner implemenation, especially since it takes advantage of Cocoa's and CFNetwork's existing support for network streams, SSL and Bonjour.
 
\subsection blipfeatures BLIP Features:

 <ul>
 <li>Each message is very much like a MIME body, as in email or HTTP: it consists of a
blob of data of arbitrary length, plus a set of key/value pairs called "properties". The
properties are mostly ignored by BLIP itself, but clients can use them for metadata about the
body, and for delivery information (i.e. something like BEEP's "profiles".)

<li>Either peer can send a request at any time; there's no notion of "client" and "server" roles.
 
<li> Multiple messages can be transmitted simultaneously in the same direction over the same connection, so a very long
message does not block any other messages from being delivered. This means that message ordering
is a bit looser than in BEEP or HTTP 1.1: the receiver will see the beginnings of messages in the
same order in which the sender posted them, but they might not <i>end</i> in that same order. (For
example, a long message will take longer to be delivered, so it may finish after messages that
were begun after it.)

<li>The sender can indicate whether or not a message needs to be replied to; the response is tagged with the
identity of the original message, to make it easy for the sender to recognize. This makes it
straighforward to implement RPC-style (or REST-style) interactions. (Responses
cannot be replied to again, however.)

<li>A message can be flagged as "urgent". Urgent messages are pushed ahead in the outgoing queue and
get a higher fraction of the available bandwidth.

<li>A message can be flagged as "compressed". This runs its body through the gzip algorithm, ideally
making it faster to transmit. (Common markup-based data formats like XML and JSON compress
extremely well, at ratios up to 10::1.) The message is decompressed on the receiving end,
invisibly to client code.
 
<li>The implementation supports SSL connections (with optional client-side certificates), and Bonjour service advertising.
</ul>
 
\section config Configuration
 
    MYNetwork requires Mac OS X 10.5 or later, since it uses Objective-C 2 features like
    properties and for...in loops.
 
    MYNetwork uses my <a href="/hg/hgwebdir.cgi/MYUtilities">MYUtilities</a> library. You'll need to have downloaded that library, and added
    the necessary source files and headers to your project. See the MYNetwork Xcode project,
    which contains the minimal set of MYUtilities files needed to build MYUtilities. (That project
    has its search paths set up to assume that MYUtilities is in a directory next to MYNetwork.)

\section download How To Get It

    <ul>
    <li><a href="/hg/hgwebdir.cgi/MYNetwork/archive/tip.zip">Download the current source code</a>
    <li>To check out the source code using <a href="http://selenic.com/mercurial">Mercurial</a>:
    \verbatim hg clone /hg/hgwebdir.cgi/MYNetwork/ MYNetwork \endverbatim
    <li>As described above, you'll also need to download or check out <a href="/hg/hgwebdir.cgi/MYUtilities">MYUtilities</a> and put it in 
    a directory next to MYNetwork.
    </ul>

    Or if you're just looking:

    <ul>
    <li><a href="/hg/hgwebdir.cgi/MYNetwork/file/tip">Browse the source code</a>
    <li><a href="annotated.html">Browse the class documentation</a>
    </ul>
 
    There isn't any conceptual documentation yet, beyond what's in the API docs, but you can 
    <a href="/hg/hgwebdir.cgi/MYNetwork/file/tip/BLIP/Demo/">look
    at the sample BLIPEcho client and server</a>, which are based on Apple's 
    <a href="http://developer.apple.com/samplecode/CocoaEcho/index.html">CocoaEcho</a> sample code.
 
 */
