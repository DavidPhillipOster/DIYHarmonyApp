//  DIYHarmonyHub.h
//  DIYHarmonyApp
//
//  Copyright © 2021 David Phillip Oster. All rights reserved.
// Open Source under Apache 2 license. See LICENSE in https://github.com/DavidPhillipOster/DIYHarmonyApp/ .
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class DIYResponse;
@protocol DIYHarmonyHubDelegate;

typedef enum {
  DIYLogOFF = 0,
  DIYLogError = 1,
  DIYLogInfo = 2,
  DIYLogVerbose = 3,
} DIYLog;


// in a changed notification, the sending object is the DIYHarmonyHub, and the previous value is in the info dict under DIYHarmonyOldKey.
extern NSString *const DIYHarmonyOldKey;

@interface DIYHarmonyHub : NSObject

@property(nonatomic, weak, readonly) id<DIYHarmonyHubDelegate> delegate;

@property(nonatomic, readonly) NSString *ip4Address;

// 0 means we don't have one yet.
@property(nonatomic, readonly) long remoteID;

// nil means we don't have one yet.
@property(nonatomic, nullable, readonly) NSArray<NSDictionary<NSString *, NSObject *> *> *activities;

// nil means we don't have one yet.
@property(nonatomic, nullable, readonly) NSDictionary<NSString *, NSObject *> *currentActivity;

// nil means we don't have one yet.
@property(nonatomic, nullable, readonly) NSArray<NSDictionary<NSString *, NSObject *> *> *devices;

// defaults to no NSLog'ing. You can change this at any time.
@property(nonatomic, class) DIYLog logLevel;

// Get the IP address of your harmony hub from your router.
- (instancetype)initWithIP4Address:(NSString *)ip4Address delegate:(nullable id<DIYHarmonyHubDelegate>)delegate;

- (void)startActivity:(NSString *)activityID completion:(void (^)(DIYResponse *response))completion;

- (void)requestButtonPressAction:(NSString *)action completion:(void (^)(DIYResponse *response))completion;

- (void)requestButtonHoldAction:(NSString *)action completion:(void (^)(DIYResponse *response))completion;

- (void)requestButtonReleaseAction:(NSString *)action completion:(void (^)(DIYResponse *response))completion;

@end

@protocol DIYHarmonyHubDelegate <NSObject>
@optional

- (void)hub:(DIYHarmonyHub *)hub activitiesChangedOld:(nullable NSArray<NSDictionary<NSString *, NSObject *> *> *)oldActivities;

- (void)hub:(DIYHarmonyHub *)hub currentActivityChangedOld:(nullable NSDictionary<NSString *, NSObject *> *)oldActivity;

- (void)hub:(DIYHarmonyHub *)hub devicesChangedOld:(nullable NSArray<NSDictionary<NSString *, NSObject *> *> *)oldDevices;
@end


NS_ASSUME_NONNULL_END
