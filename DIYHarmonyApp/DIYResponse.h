//
//  DIYResponse.h
//  DIYHarmonyApp
//
//  Created by david on 1/10/21.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef enum {
  DIYResponseTypeResponse,
  DIYResponseTypeError,
} DIYResponseType;

/// Objective-C model of a Swift Response object. responseType says which of only one of the fields is non nil.
@interface DIYResponse : NSObject
@property(readonly) DIYResponseType responseType;
@property(readonly) NSDictionary *json;
@property(readonly) NSError *error;

+ (instancetype)withError:(NSError *)error;
+ (instancetype)withJSON:(NSDictionary *)json;

@end

NS_ASSUME_NONNULL_END
