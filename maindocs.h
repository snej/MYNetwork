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
 
    \section config Configuration
 
    MYNetwork requires Mac OS X 10.5 or later, since it uses Objective-C 2 features like
    properties and for...in loops.
 
    MYNetwork uses my <a href="/hg/hgwebdir.cgi/MYUtilities">MYUtilities</a> library. You'll need to have downloaded that library, and added
    the necessary source files and headers to your project. See the MYNetwork Xcode project,
    which contains the minimal set of MYUtilities files needed to build MYUtilities. (That project
    has its search paths set up to assume that MYUtilities is in a directory next to MYNetwork.)

    \section download How To Get It

    <ul>
    <li><a href="http://mooseyard.com/hg/hgwebdir.cgi/MYNetwork/archive/tip.zip">Download the current source code</a>
    <li>To check out the source code using <a href="http://selenic.com/mercurial">Mercurial</a>:
    \verbatim hg clone http://mooseyard.com/hg/hgwebdir.cgi/MYNetwork/ MYNetwork \endverbatim
    </ul>

    Or if you're just looking:

    <ul>
    <li><a href="http://mooseyard.com/hg/hgwebdir.cgi/MYNetwork/file/tip">Browse the source code</a>
    <li><a href="annotated.html">Browse the class documentation</a>
    </ul>
 
 */
