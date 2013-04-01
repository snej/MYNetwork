//
//  TCPEndpoint+Certs.m
//  MYNetwork-iPhone
//
//  Created by Jens Alfke on 5/21/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import "TCPEndpoint.h"
#import "CollectionUtils.h"
#import <Security/Security.h>


/** These are some optional category methods for TCPEndpoint for dumping info about certificates.
    They're useful if you're working with SSL connections, but they do link against the Security
    framework, so they're moved into this extra file that you can choose to compile into your
    project or not.
*/
@implementation TCPEndpoint (Certificates)


+ (NSString*) describeCert: (SecCertificateRef)cert {
    if (!cert)
        return @"(null)";
    NSString *desc;
#if TARGET_OS_IPHONE && !defined(__SEC_TYPES__)
    NSString* summary = CFBridgingRelease(SecCertificateCopySubjectSummary(cert));
    desc = $sprintf(@"Certificate[%@]", summary);
#else
    CFStringRef cfName=NULL;
    CFArrayRef cfEmails=NULL;
    SecCertificateCopyCommonName(cert, &cfName);
    SecCertificateCopyEmailAddresses(cert, &cfEmails);
    NSString* name = CFBridgingRelease(cfName);
    NSArray* emails = CFBridgingRelease(cfEmails);
    desc = $sprintf(@"Certificate[\"%@\", <%@>]",
                    name, [emails componentsJoinedByString: @">, <"]);
#endif
    return desc;
}

+ (NSString*) describeIdentity: (SecIdentityRef)identity {
    if (!identity)
        return @"(null)";
    SecCertificateRef cert;
    SecIdentityCopyCertificate(identity, &cert);
    return $sprintf(@"Identity[%@]", [self describeCert: cert]);
}


@end
