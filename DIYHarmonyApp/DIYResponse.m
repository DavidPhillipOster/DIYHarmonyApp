//  DIYResponse.m
//  DIYHarmonyApp
//
//  Copyright © 2021 David Phillip Oster. All rights reserved.
// Open Source under Apache 2 license. See LICENSE in https://github.com/DavidPhillipOster/DIYHarmonyApp/ .
//

#import "DIYResponse.h"

@interface DIYResponse()
@property(readwrite) DIYResponseType responseType;
@property(readwrite) NSDictionary *json;
@property(readwrite) NSError *error;
@end

@implementation DIYResponse

+ (instancetype)withError:(NSError *)error {
  DIYResponse *result = [[DIYResponse alloc] init];
  result.responseType = DIYResponseTypeError;
  result.error = error;
  return result;
}

+ (instancetype)withJSON:(NSDictionary *)json {
  DIYResponse *result = [[DIYResponse alloc] init];
  result.responseType = DIYResponseTypeResponse;
  result.json = json;
  return result;
}

@end
