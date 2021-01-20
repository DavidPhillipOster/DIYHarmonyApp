//  DIYPreferencesController.m
//  DIYHarmonyApp
//
//  Copyright © 2021 David Phillip Oster. All rights reserved.
// Open Source under Apache 2 license. See LICENSE in https://github.com/DavidPhillipOster/DIYHarmonyApp/ .
//

#import "DIYPreferencesController.h"

@interface DIYPreferencesController ()
@property IBOutlet NSTextField *hubIP;
@end

static BOOL IsValidIP4String(NSString *s) {
  NSArray *parts = [s componentsSeparatedByString:@"."];
  if (4 != [parts count]) {  return NO; }
  for (NSString *part in parts) {
    if (0 == [part length]) { return NO; }
    unichar c = [part characterAtIndex:0];
    if ( ! ('0' <= c && c <= '9')) { return NO; }
    int n = [part intValue];
    if ( ! (0 <= n && n <= 255)) { return NO; }
  }
  return YES;
}

@implementation DIYPreferencesController

- (void)windowDidLoad {
  [super windowDidLoad];
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  NSString *hubIP = [ud objectForKey:@"hubIP"];
  self.hubIP.stringValue = hubIP;
}

- (void)textDidChange:(NSNotification *)notification {
  NSString *hubIP = self.hubIP.stringValue;
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  if (0 == [hubIP length]) {
    [ud removeObjectForKey:@"hubIP"];
  } else if (IsValidIP4String(hubIP)) {
    [ud setObject:hubIP forKey:@"hubIP"];
  }
}

@end
