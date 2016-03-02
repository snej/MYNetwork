//
//  BLIPFileRequest.h
//
//  Created by Matthew Nespor on 2/24/14.
//  Copyright (c) 2014 Nanonation. All rights reserved.
//

@interface BLIPFileRequest : BLIPRequest

@property (strong, nonatomic) NSString* expectedHash;
@property (strong, nonatomic) NSString* outFilePath;
@property (strong, nonatomic) NSString* inFilePath;

+ (instancetype)pushRequestWithBodyFilePath:(NSString*)filePath
                                 properties:(NSDictionary*)properties
                            completionBlock:(void (^)(BLIPResponse* response))completionBlock;

+ (instancetype)pullRequestWithProperties:(NSDictionary*)properties
                          destinationPath:(NSString*)destinationPath
                             expectedHash:(NSString*)hash
                          completionBlock:(void (^)(BLIPResponse* response))completionBlock;

@end
