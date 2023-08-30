//  DIYHarmonyHub.m
//  DIYHarmonyApp
//
//  Copyright © 2021 David Phillip Oster. All rights reserved.
// Open Source under Apache 2 license. See LICENSE in https://github.com/DavidPhillipOster/DIYHarmonyApp/ .
//

#import "DIYHarmonyHub.h"
#import "DIYResponse.h"

NSNotificationName DIYHarmonyActivitiesChanged = @"DIYHarmonyActivitiesChanged";
NSNotificationName DIYHarmonyDevicesChanged = @"DIYHarmonyDevicesChanged";


static NSString *const activeRemoteIdKey = @"activeRemoteId";
/// for simplicity, I use the same key for NSUserDefaults that Harmony uses for its json.
static NSString *const activityKey = @"activity";
static NSString *const deviceKey = @"device";

@interface DIYHarmonyHub() <NSURLSessionDataDelegate>
@property(nonatomic, weak, readwrite) id<DIYHarmonyHubDelegate> delegate;
@property(nonatomic, copy, readwrite) NSString *ip4Address;
@property(nonatomic, readwrite) long remoteID;
@property(nonatomic, readonly) NSString *nextSequenceNumber;
@property(nonatomic, nullable, readwrite) NSArray<NSDictionary<NSString *, NSObject *> *> *activities;
@property(nonatomic, nullable, readwrite) NSDictionary<NSString *, NSObject *> *currentActivity;
@property(nonatomic, nullable, readwrite) NSArray<NSDictionary<NSString *, NSObject *> *> *devices;
@property(nonatomic) NSURLSession *session;
@property(nonatomic) NSURLSessionTask *postTask;
@property(nonatomic) NSURLSessionWebSocketTask *webTask;
@property(nonatomic) NSMutableDictionary<NSString *, void (^)(DIYResponse *)> *idsToCompletions;
@end

// since DIYHarmonyHub can do a lot of work in its init, logging control is a class property
// so you can set it before you create a DIYHarmonyHub object.
static DIYLog slogLevel;

@implementation DIYHarmonyHub
@synthesize nextSequenceNumber = _nextSequenceNumber;

+ (DIYLog)logLevel {
  return slogLevel;
}

+ (void)setLogLevel:(DIYLog)logLevel {
  slogLevel = logLevel;
}

-  (instancetype)initWithIP4Address:(NSString *)ip4Address delegate:(nullable id<DIYHarmonyHubDelegate>)delegate{
  self = [super init];
  if (self) {
    _delegate = delegate;
    _idsToCompletions = [NSMutableDictionary dictionary];
    _ip4Address = ip4Address;
    NSNumber *remoteNumber = [NSUserDefaults.standardUserDefaults valueForKey:activeRemoteIdKey];
    _remoteID = [remoteNumber longValue];
    self.activities = [self jsonArrayFromURL:[self activitiesURL]];
    self.devices = [self jsonArrayFromURL:[self devicesURL]];
    [self updateConfigurationIfNeeded];
    [self updateCurrentActivityIfPossible];
  }
  return self;
}

- (void)updateConfigurationIfNeeded {
  if (0 == self.remoteID) {
    __weak typeof(self) weakself = self;
    [self requestAccountInfoCompletion:^(DIYResponse *response){
      [weakself handleAccountInfoResponse:response];
    }];
  } else {
    [self updateActivitiesAndDevicesIfNeeded];
  }
}

- (void)updateActivitiesAndDevicesIfNeeded {
  if (nil == self.activities || nil == self.devices) {
    __weak typeof(self) weakself = self;
    [self requestActivitiesAndDevices:^(DIYResponse *response){
      [weakself handleActivitiesAndDevicesResponse:response];
    }];
  }
}

- (void)updateCurrentActivityIfPossible {
  if (0 != self.remoteID && nil != self.activities && nil != self.devices) {
    __weak typeof(self) weakself = self;
    [self requestCurrentActivity:^(DIYResponse *response){
      [weakself handleCurrentActivityResponse:response andThen:^(DIYResponse *response) {}];
    }];
  }
}

// Save the completion block for later. Key is the task it.
- (void)setCompletion:(void (^)(DIYResponse *))completion messageID:(NSString *)identifier {
  self.idsToCompletions[identifier] = completion;
}

// Look up the completion block by task id. call it.
// TO DO: diagnostics for: if never called, if called multiple times.
- (void)deliverResponse:(DIYResponse *)response messageID:(NSString *)identifier {
  void (^completion)(DIYResponse *) = self.idsToCompletions[identifier];
  if (completion) {
    self.idsToCompletions[identifier] = nil;
    completion(response);
  }
}

// Callback for requestAccountInfoCompletion:
- (void)handleAccountInfoResponse:(DIYResponse *)response {
  if (response.responseType == DIYResponseTypeResponse) {
    NSDictionary *innerDict = response.json[@"data"];
    long remoteID = [innerDict[activeRemoteIdKey] longValue];
    if (remoteID) {
      NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
      [ud setValue:@(remoteID) forKey:activeRemoteIdKey.description];
      [ud synchronize];
      self.remoteID = remoteID;
      __weak typeof(self) weakself = self;
      [self requestActivitiesAndDevices:^(DIYResponse *response){
        [weakself handleActivitiesAndDevicesResponse:response];
      }];
    }
    [self logVerbose:response.json cmd:_cmd];
  } else {
    [self logError:response.error cmd:_cmd];
  }
}

- (void)requestAccountInfoCompletion:(void (^)(DIYResponse *))completion {
  NSMutableURLRequest *request = [self postRequest];
  NSString *identifier = [self nextSequenceNumber];
  NSDictionary *dict = @{
    @"cmd" : @"setup.account?getProvisionInfo",
    @"id": @([identifier integerValue]),
    @"timeout": @(90000),
  };
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&error];
  if (error) {
    completion([DIYResponse withError:error]);
  } else {
    request.HTTPBody = data;
    self.postTask = [self.session dataTaskWithRequest:request];
    [self setCompletion:completion messageID:identifier];
    [self.postTask resume];
  }
}

- (void)setActivities:(NSArray<NSDictionary<NSString *,NSObject *> *> *)activities {
  if (_activities != activities) {
    NSArray<NSDictionary<NSString *,NSObject *> *> *oldActivities = _activities;
    _activities = activities;
    if ([self.delegate respondsToSelector:@selector(hub:activitiesChangedOld:)]) {
      [self.delegate hub:self activitiesChangedOld:oldActivities];
    }
  }
}

- (void)setDevices:(NSArray<NSDictionary<NSString *,NSObject *> *> *)devices {
  if (_devices != devices) {
    NSArray<NSDictionary<NSString *,NSObject *> *> *oldDevices = _devices;
    _devices = devices;
    if ([self.delegate respondsToSelector:@selector(hub:devicesChangedOld:)]) {
      [self.delegate hub:self devicesChangedOld:oldDevices];
    }
  }
}

- (void)handleCurrentActivityResponse:(DIYResponse *)response andThen:(void (^)(DIYResponse *response))completion {
  if (response.responseType == DIYResponseTypeResponse) {
    [self logVerbose:response.json cmd:_cmd];
    NSDictionary *dict = response.json;
    NSString *activityID = dict[@"data"][@"result"];
    if (activityID) {
      for (NSDictionary *json in self.activities) {
        if ([json[@"id"] isEqual:activityID]) {
          self.currentActivity = json;
          break;
        }
      }
    } else {
      NSString *runningActivity = dict[@"data"][@"runningActivityList"];
      if (nil != runningActivity && [runningActivity isEqual:self.currentActivity[@"id"]]) {
        __weak typeof(self) weakself = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          [weakself requestCurrentActivity:^(DIYResponse *response2) {
            [weakself handleCurrentActivityResponse:response2 andThen:completion];
          }];
        });
        return;
      }
    }
  }
  completion(response);
}

- (void)setCurrentActivity:(NSDictionary<NSString *,NSObject *> *)currentActivity {
  if (_currentActivity != currentActivity) {
    NSDictionary<NSString *,NSObject *> *oldActivity = _currentActivity;
    _currentActivity = currentActivity;
    if ([self.delegate respondsToSelector:@selector(hub:currentActivityChangedOld:)]) {
      [self.delegate hub:self currentActivityChangedOld:oldActivity];
    }
  }
}

- (NSURLSession *)session {
  if (nil == _session) {
    self.session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration delegate:self delegateQueue:nil];
  }
  return _session;
}

  // The id is a "random" non-rpeeating number.
- (NSString *)nextSequenceNumber {
  static long start = 0;
  if (0 == start) {
    while (0 == start) {
      start = (unsigned int)[NSDate timeIntervalSinceReferenceDate];
    }
    if (start < 0) {
      start = labs(start);
    }
    start = start % 10000;
  }
  return [NSString stringWithFormat:@"%ld", ++start];
}

- (NSMutableURLRequest *)postRequest {
  NSString *urlString = [NSString stringWithFormat:@"http://%@:8088", self.ip4Address];
  NSURL *url = [NSURL URLWithString:urlString];
  return [self postRequestForURL:url];
}

- (NSMutableURLRequest *)postRequestForURL:(NSURL *)url {
  NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
  request.HTTPMethod = @"POST";
  request.allHTTPHeaderFields = @{
    @"Origin" : @"http://sl.dhg.myharmony.com",
    @"Content-Type" : @"application/json",
    @"Accept" : @"utf-8",
  };
  return request;
}

- (NSURL *)webSocketURL {// http
  NSString *urlString = [NSString stringWithFormat:@"ws://%@:8088?domain=svcs.myharmony.com&hubId=%ld", self.ip4Address, self.remoteID];
  NSURL *url = [NSURL URLWithString:urlString];
  return url;
}

// Callback for requestActivitiesAndDevices:
- (void)handleActivitiesAndDevicesResponse:(DIYResponse *)response {
  if (response.responseType == DIYResponseTypeResponse) {
    NSDictionary *innerDict = response.json[@"data"];
    self.activities = innerDict[activityKey];
    // TODO nil error report here.
    self.devices = innerDict[deviceKey];
    // TODO nil error report here.
    if (self.activities) {
      NSData *data = [NSJSONSerialization dataWithJSONObject:self.activities options:0 error:NULL];
      NSError *error = nil;
      [data writeToURL:[self activitiesURL] options:0 error:&error];
      if (error) { [self logError:error cmd:_cmd]; }
    }
    if (self.devices) {
      NSData *data = [NSJSONSerialization dataWithJSONObject:self.devices options:0 error:NULL];
      NSError *error = nil;
      [data writeToURL:[self devicesURL] options:0 error:&error];
      if (error) { [self logError:error cmd:_cmd]; }
    }
    [self updateCurrentActivityIfPossible];
    [self logVerbose:response.json cmd:_cmd];
  }
}

// Assume each message this sends will get a response with a matching sequence number.
// send the response to the completion, wrapped in a DIYResponse to handle the error case.
- (void)webSocketMessage:(NSDictionary *)jsonMessage completion:(void (^)(DIYResponse *))completion {
  [self webSocketMessage:jsonMessage retries:0 completion:completion];
}

- (void)webSocketMessage:(NSDictionary *)jsonMessage retries:(int)retries completion:(void (^)(DIYResponse *))completion {
  if (nil == self.webTask) {
    NSURL *url = [self webSocketURL];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request addValue:@"http://sl.dhg.myharmony.com" forHTTPHeaderField:@"Origin"];
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request addValue:@"utf-8" forHTTPHeaderField:@"Accept"];
    self.webTask = [self.session webSocketTaskWithRequest:request];
    [self.webTask resume];
  }
  NSString *identifier = jsonMessage[@"id"];
  if (nil == identifier) {
    identifier = jsonMessage[@"hbus"][@"id"];
  }
  [self setCompletion:completion messageID:identifier];
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:jsonMessage options:0 error:&error];
  NSURLSessionWebSocketMessage *mesg = [[NSURLSessionWebSocketMessage alloc] initWithData:data];
  __weak typeof(self) weakself = self;
  [self.webTask receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError * error) {
    NSError *errorJ = error;
    NSDictionary *json = nil;
    DIYResponse *response = nil;
    if (nil == errorJ) {
      NSData *data = message.data;
      if (nil == data) {
        data = [message.string dataUsingEncoding:NSUTF8StringEncoding];
      }
      json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&errorJ];
    }
    if (errorJ) {
      [weakself logError:error cmd:_cmd];
      if (error.code == 57 && [error.domain isEqual:NSPOSIXErrorDomain] && retries == 0) {
        weakself.webTask = nil;
        [weakself webSocketMessage:jsonMessage retries:retries + 1 completion:completion];
        return;
      }
      response = [DIYResponse withError:error];
    } else {
      response = [DIYResponse withJSON:json];
    }
    [weakself deliverResponse:response messageID:identifier];
  }];
  [self.webTask sendMessage:mesg completionHandler:^(NSError * error){
    if (error) {
      [weakself logError:error cmd:_cmd];
      DIYResponse *response = [DIYResponse withError:error];
      [weakself deliverResponse:response messageID:identifier];
    }
  }];
}

// @"-1" means Power Off activity is current.
/*
{
  "cmd": "vnd.logitech.harmony/vnd.logitech.harmony.engine?getCurrentActivity",
  "code": 200,
  "id": "0",
  "msg": "OK",
  "data": {
    "result": "-1" // id of currentactivity returned here.
  }
}
 */
- (void)requestCurrentActivity:(void (^)(DIYResponse *))completion {
  NSDictionary *dict = @{
    @"hubId": @(self.remoteID),
    @"timeout": @(30),
    @"hbus": @{
        @"cmd": @"vnd.logitech.harmony/vnd.logitech.harmony.engine?getCurrentActivity",
        @"id": [self nextSequenceNumber],
        @"params": @{
            @"verb": @"get"
        }
    }
  };
  [self webSocketMessage:dict completion:completion];
}

/*
 {
  "type": "vnd.logitech.harmony\/vnd.logitech.harmony.engine?startActivityFinished",
  "data": {
  	"activityId": "-1",
	"errorCode": 200,
  	"errorString": "OK"
  }
}
 */
- (void)startActivity:(NSString *)activityID completion:(void (^)(DIYResponse *))completion {
  NSDictionary *dict = @{
    @"hubId": @(self.remoteID),
    @"timeout": @(60),
    @"hbus": @{
        @"cmd": @"vnd.logitech.harmony/vnd.logitech.harmony.engine?startactivity",
        @"id": [self nextSequenceNumber],
        @"params": @{
            @"async": @"true",
            @"timestamp": @(0),
            @"args": @{
                @"rule": @"start"
            },
            @"activityId": activityID,
        }
    }
  };
  [self logVerbose:activityID cmd:_cmd];
  __weak typeof(self) weakself = self;
  [self webSocketMessage:dict completion:^(DIYResponse *response) {
    if (response.responseType == DIYResponseTypeError) {
      completion(response);
    } else {
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakself requestCurrentActivity:^(DIYResponse *response2) {
          [weakself handleCurrentActivityResponse:response2 andThen:completion];
        }];
      });
    }
  }];
}

- (void)requestButtonPressAction:(NSString *)action completion:(void (^)(DIYResponse *response))completion {
  [self requestButtonAction:@"press" action:action completion:completion];
}

- (void)requestButtonHoldAction:(NSString *)action completion:(void (^)(DIYResponse *response))completion {
  [self requestButtonAction:@"hold" action:action completion:completion];
}

- (void)requestButtonReleaseAction:(NSString *)action completion:(void (^)(DIYResponse *response))completion {
  [self requestButtonAction:@"release" action:action completion:completion];
}


// actions are stored in the activity and device tree.
- (void)requestButtonAction:(NSString *)verbString action:(NSString *)action completion:(void (^)(DIYResponse *))completion {
  NSDictionary *dict = @{
    @"hubId":  @(self.remoteID),
    @"timeout": @(30),
    @"hbus": @{
        @"cmd": @"vnd.logitech.harmony/vnd.logitech.harmony.engine?holdAction",
        @"id": [self nextSequenceNumber],
        @"params": @{
            @"status": verbString,
            @"timestamp": @"0",
            @"verb": @"render",
            @"action": action
        }
    }
  };
  [self logVerbose:dict cmd:_cmd];
  [self webSocketMessage:dict completion:completion];
}


- (void)requestActivitiesAndDevices:(void (^)(DIYResponse *))completion {
  NSDictionary *dict = @{
    @"hubId" : @(self.remoteID),
    @"timeout": @(60),
    @"hbus": @{
      @"cmd" : @"vnd.logitech.harmony/vnd.logitech.harmony.engine?config",
      @"id": [self nextSequenceNumber],
      @"params": @{ @"verb": @"get"}
    },
  };
  [self webSocketMessage:dict completion:completion];
}



- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(nullable NSError *)error {
  [self logError:error cmd:_cmd];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
  NSError *error = nil;
  NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  DIYResponse *response = nil;
  NSString *identifier = nil;
  if (error) {
    response = [DIYResponse withError:error];
    [self logError:error cmd:_cmd];
  }
  if (dict) {
    response = [DIYResponse withJSON:dict];
    identifier = dict[@"id"];
    [self logVerbose:dict cmd:_cmd];
  }
  if (nil == identifier) {
    identifier = self.idsToCompletions.allKeys.firstObject;
  }
  [self deliverResponse:response messageID:identifier.description];  //kludge
  if (dataTask == self.postTask) {
    self.postTask = nil;
  }
}

- (void)URLSession:(NSURLSession *)session
            dataTask:(NSURLSessionDataTask *)dataTask
  didReceiveResponse:(NSURLResponse *)response
   completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
  if (response) {
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
      NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
      if (httpResponse.statusCode != 200) {
        completionHandler(NSURLSessionResponseCancel);
        completionHandler = nil;
        NSError *error = dataTask.error ? dataTask.error : [NSError errorWithDomain:NSURLErrorDomain code:httpResponse.statusCode userInfo:nil];
        DIYResponse *response = [DIYResponse withError:error];
        [self deliverResponse:response messageID:self.idsToCompletions.allKeys.firstObject];  //kludge
        if (dataTask == self.postTask) {
          self.postTask = nil;
        }
      }
    }
    [self logVerbose:response cmd:_cmd];
  }
  if (completionHandler) {
    completionHandler(NSURLSessionResponseAllow);
  }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
                                didBecomeStreamTask:(NSURLSessionStreamTask *)streamTask {
   [self logVerbose:streamTask cmd:_cmd];
}

- (void)URLSession:(NSURLSession *)session readClosedForStreamTask:(NSURLSessionStreamTask *)streamTask {
   [self logVerbose:streamTask cmd:_cmd];
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didOpenWithProtocol:(NSString * _Nullable) protocol {
  // does get called. protocol is nil.
  [self logVerbose:protocol cmd:_cmd];
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode reason:(NSData * _Nullable)reason {
   [self logVerbose:[[NSArray alloc] initWithObjects:webSocketTask, @(closeCode), reason, nil] cmd:_cmd];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
                           didCompleteWithError:(nullable NSError *)error {
  [self logVerbose:error cmd:_cmd];
}

/// Given a file URL, return the contents as an array of dictionaries, else nil.
- (NSArray<NSDictionary<NSString *, NSObject *> *> *)jsonArrayFromURL:(NSURL *)url {
  NSData *data = [NSData dataWithContentsOfURL:url];
  if (nil == data) {
    return nil;
  }
  NSArray *result = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
  if ( ! [result isKindOfClass:[NSArray class]]) {
    return nil;
  }
  return result;
}

/// The directory where cached activities and devices are written.
- (NSURL *)supportURL {
  NSFileManager *fm = [NSFileManager defaultManager];
  return [[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
}

- (NSURL *)activitiesURL {
  return [[self supportURL] URLByAppendingPathComponent:@"activities.json"];
}

- (NSURL *)devicesURL {
  return [[self supportURL] URLByAppendingPathComponent:@"devices.json"];
}

- (void)logVerbose:(NSObject *)mesg cmd:(SEL)cmd  {
  if (DIYLogVerbose <= self.class.logLevel) {
    NSLog(@"%@ %@", NSStringFromSelector(cmd), mesg);
  }
}

- (void)logInfo:(NSObject *)mesg cmd:(SEL)cmd  {
  if (DIYLogInfo <= self.class.logLevel) {
    NSLog(@"%@ %@", NSStringFromSelector(cmd), mesg);
  }
}

- (void)logError:(NSObject *)mesg cmd:(SEL)cmd {
  if (DIYLogError <= self.class.logLevel) {
    NSLog(@"%@ %@", NSStringFromSelector(cmd), mesg);
  }
}

@end
