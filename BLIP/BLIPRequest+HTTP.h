//
//  BLIPRequest+HTTP.h
//  MYNetwork
//
//  Created by Jens Alfke on 4/15/13.
//
//


/** Methods for converting a BLIPRequest to and from an HTTP NSURLRequest. */
@interface BLIPRequest (HTTP)

// Creates a BLIPRequest from an NSURLRequest.
+ (instancetype) requestWithHTTPRequest: (NSURLRequest*)httpRequest;

// Creates an NSURLRequest from a BLIPRequest.
- (NSURLRequest*) asHTTPRequest;

@end


/** Methods for converting a BLIPResponse to and from an NSHTTPURLResponse. */
@interface BLIPResponse (HTTP)

// Stores an HTTP response into a BLIPResponse.
- (void) setHTTPResponse: (NSHTTPURLResponse*)httpResponse
                withBody: (NSData*)httpBody;

// Creates an HTTP response from a BLIPResponse.
- (NSHTTPURLResponse*) asHTTPResponseWithBody: (NSData**)outHTTPBody
                                       forURL: (NSURL*)url;

@end
