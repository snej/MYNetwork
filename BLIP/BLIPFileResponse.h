//
//  BLIPFileResponse.h
//
//  Created by Matthew Nespor on 2/24/14.
//  Copyright (c) 2014 Nanonation. All rights reserved.
//

@interface BLIPFileResponse : BLIPResponse

@property (strong, nonatomic) NSString* expectedHash;
@property (strong, nonatomic) NSString* path;
@property (copy, nonatomic) void (^completionBlock)(BLIPResponse* response);

@end
