# MYNetwork: Mooseyard Networking Library, With BLIP Protocol Implementation #
 
By [Jens Alfke](mailto:jens@mooseyard.com)

## Introduction ##
 
MYNetwork is a set of Objective-C networking classes for Cocoa applications on Mac OS X or iOS.
It consists of:

* An implementation of **[BLIP](https://bitbucket.org/snej/mynetwork/wiki/BLIP/Overview)**, a lightweight network protocol I've invented as an easy way to send request and response messages between peers. (see BLIPListener, BLIPConnection, BLIPRequest, etc.)
* A generic TCP client/server implementation, useful for implementing your own network protocols; (see TCPListener and TCPConnection)
* Networking utility classes:
 * IPAddress, an abstraction for IPv4 addresses
 * PortMapper, a way to make services on a computer behind a NAT router available to computers outside
 * Higher-level Bonjour APIs like BonjourBrowser and BonjourService.

_(Details available in the [API documentation](https://bitbucket.org/snej/mynetwork/wiki/Documentation/html/annotated.html).)_

MYNetwork has been publicly available since May 2008. It's been used in several shipping Mac and iOS applications by multiple developers.

> “An awesome network library ... It made moving pages from [VoodooPad](http://flyingmeat.com/voodoopad) to the the iPhone over the network completely painless. A++ would recommend again.” [*](http://gusmueller.com/blog/archives/2009/03/voodoopad_4.1_and_vp_reader_for_iphone_released.html)  
> --Gus Mueller, [Flying Meat Software](http://flyingmeat.com)
 
If you come across bugs, please tell me about them. If you fix them, I would love to get your fixes and incorporate them. If you add features I would love to know about them, and I will incorporate them if I think they make sense for the project. Thanks!

## What's BLIP? ##
 
[BLIP](https://bitbucket.org/snej/mynetwork/wiki/BLIP/Overview) is a message-oriented network protocol that lets the two peers on either end of a TCP socket send request and response messages to each other. It's a generic protocol, in that the requests and responses can contain any kind of data you like. It's somewhat like Jabber/XMPP, and somewhat like HTTP, and a lot like [BEEP](https://bitbucket.org/snej/mynetwork/wiki/BLIP/BEEP).

You can read a more detailed [overview](https://bitbucket.org/snej/mynetwork/wiki/BLIP/Overview) of BLIP, or examine the [protocol specification](https://bitbucket.org/snej/mynetwork/wiki/BLIP/Protocol).

(Unlike the other Mac/iPhone-specific code here, BLIP comes with a platform-independent Python implementation as well.)

## Getting Started ##

Are you sold already? Then **please read the [Setup instructions](https://bitbucket.org/snej/mynetwork/wiki/Setup).** MYNetwork uses the separate MYUtilities library (see [Git](http://github.com/snej/MYUtilities) and [Mercurial](https://bitbucket.org/snej/myutilities/) repos), and you have to do a little bit of one-time configuration to link the projects together, or you'll get weird errors.

## What Do the Generic Classes Do? ##

For some reason the Cocoa frameworks don't include a way to create a TCP server (also known as a listener), only a client connection. To implement a server, you have to use some low-level procedural APIs in CoreFoundation.

Additionally, there are some annoying limitations of the NSStream API, particularly when writing -- NSOutputStream doesn't do any buffering, so you're in charge of spoon-feeding it data at the rate it can handle it. MYNetwork's TCPWriter takes care of that.

There also turns out to be some complicated logic required for implementing time-outs when attempting to connect, and also for closing down a socket connection cleanly. TCPConnection manages that.

## License ##
 
MYNetwork is released under a BSD license, which means you can freely use it in open-source
or commercial projects, provided you give credit in your documentation or About box.
