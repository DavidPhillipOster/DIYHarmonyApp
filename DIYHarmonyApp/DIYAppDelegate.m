//  AppDelegate.m
//  DIYHarmonyApp
//
//  Copyright © 2021 David Phillip Oster. All rights reserved.
// Open Source under Apache 2 license. See LICENSE in https://github.com/DavidPhillipOster/DIYHarmonyApp/ .
//

#import "DIYAppDelegate.h"

#import "DIYHarmonyHub.h"
#import "DIYPreferencesController.h"
#import "DIYResponse.h"

@interface DIYAppDelegate () <
  DIYHarmonyHubDelegate,
  NSOutlineViewDataSource,
  NSOutlineViewDelegate,
  NSToolbarDelegate>

@property NSWindowController *prefController;
@property IBOutlet NSWindow *window;
@property IBOutlet NSView *contentView;
@property IBOutlet NSToolbar *toolbar;
@property IBOutlet NSScrollView *activityScroll;
@property IBOutlet NSOutlineView *activityList;
@property IBOutlet NSScrollView *deviceScroll;
@property IBOutlet NSOutlineView *deviceList;
@property DIYHarmonyHub *hub;
@end

@implementation DIYAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  DIYHarmonyHub.logLevel = DIYLogVerbose;
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  [ud registerDefaults:@{ @"hubIP" : @"10.0.1.2" }];
  NSString *hubIP = [ud objectForKey:@"hubIP"];
  self.hub = [[DIYHarmonyHub alloc] initWithIP4Address:hubIP delegate:self];
  NSString *toolbarItemID = [NSUserDefaults.standardUserDefaults objectForKey:@"toolbar"];
  if (nil == toolbarItemID) {
    toolbarItemID = @"Activities";
  }
  if ([toolbarItemID isEqual:@"Devices"]) {
    [self showDevices:nil];
  } else {
    [self showActivities:nil];
  }
  [self.toolbar setSelectedItemIdentifier:toolbarItemID];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
  // Insert code here to tear down your application
}

#pragma mark -

- (IBAction)showPreferences:(id)sender {
  if (self.prefController == nil) {
    self.prefController = [[DIYPreferencesController alloc] initWithWindowNibName:@"DIYPreferences"];
  }
  [self.prefController.window makeKeyAndOrderFront:nil];
}

- (IBAction)showActivities:(id)sender {
  if (self.deviceScroll.superview == self.contentView) {
    [self.deviceScroll removeFromSuperview];
  }
  CGRect frame = self.contentView.bounds;
  self.activityScroll.frame = frame;
  [self.contentView addSubview:self.activityScroll];
  [self.activityList reloadData];
  [NSUserDefaults.standardUserDefaults setObject:@"Activities" forKey:@"toolbar"];
}

- (IBAction)showDevices:(id)sender {
  if (self.activityScroll.superview == self.contentView) {
    [self.activityScroll removeFromSuperview];
  }
  CGRect frame = self.contentView.bounds;
  self.deviceScroll.frame = frame;
  [self.contentView addSubview:self.deviceScroll];
  [self.deviceList reloadData];
  [NSUserDefaults.standardUserDefaults setObject:@"Devices" forKey:@"toolbar"];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar {
  return @[@"Activities", @"Devices"];
}

#pragma mark -

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item {
  if (item == nil) {
    if (outlineView == self.deviceList) {
      return self.hub.devices.count;
    } else if (outlineView == self.activityList) {
      return self.hub.activities.count;
    }
  } else if ([item isKindOfClass:[NSDictionary class]]) {
    NSArray *controls = [item objectForKey:@"controlGroup"];
    if (nil == controls) {
      controls = [item objectForKey:@"function"];
    }
    if([controls isKindOfClass:[NSArray class]]) {
      return [controls count];
    }
  }
  return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item {
  if (item == nil) {
    if (outlineView == self.deviceList) {
      return self.hub.devices[index];
    } else if (outlineView == self.activityList) {
      return self.hub.activities[index];
    }
  } else if ([item isKindOfClass:[NSDictionary class]]) {
    NSArray *controls = [item objectForKey:@"controlGroup"];
    if (nil == controls) {
      controls = [item objectForKey:@"function"];
    }
    if([controls isKindOfClass:[NSArray class]]) {
      return controls[index];
    }
  }
  return [NSNull null];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
  if ([item isKindOfClass:[NSDictionary class]]) {
    NSArray *controls = [item objectForKey:@"controlGroup"];
    if (nil == controls) {
      controls = [item objectForKey:@"function"];
    }
    return [controls isKindOfClass:[NSArray class]] && 0 != [controls count];
  }
  return NO;
}

- (nullable NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(nullable NSTableColumn *)tableColumn item:(id)item {
  NSTableCellView *view = [outlineView makeViewWithIdentifier:@"cell" owner:nil];
  NSString *value = nil;
  NSColor *backColor = [NSColor controlTextColor];
  if ([item isKindOfClass:[NSDictionary class]]) {
    NSDictionary *dict = (NSDictionary *)item;
    value = dict[@"label"];
    if (nil == value) {
      value = dict[@"name"];
    }
    if (dict == self.hub.currentActivity) {
      backColor = [NSColor systemRedColor];
    }
  } else if ([item isKindOfClass:[NSString class]]) {
    value = (NSString *)item;
  }
  if (nil == value) {
    value = @"";
  }
  view.textField.textColor = backColor;
  view.textField.stringValue = value;
  return view;
}

- (IBAction)doDoubleClick:(NSOutlineView *)sender {
  id thing = [sender itemAtRow:sender.clickedRow];
  if ([self.hub.activities containsObject:thing]) {
    NSDictionary *activityDictionary = (NSDictionary *)thing;
    NSString *activityID = activityDictionary[@"id"];
    if ([activityID length]) {
      [self.hub startActivity:activityID completion:^(DIYResponse *response) {
        if (response.responseType == DIYResponseTypeError) {
        }
      }];
    }
  } else if ([thing isKindOfClass:[NSDictionary class]]) {
    NSDictionary *buttonDictionary = (NSDictionary *)thing;
    NSString *action = buttonDictionary[@"action"];
    if ([action isKindOfClass:[NSString class]]) {
      [self.hub requestButtonPressAction:action completion:^(DIYResponse * response) {
        if (response.responseType == DIYResponseTypeError) {
        }
      }];
    }
  }
}

#pragma mark -

- (void)hub:(DIYHarmonyHub *)hub activitiesChangedOld:(nullable NSArray<NSDictionary<NSString *, NSObject *> *> *)oldActivities {
  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
    [self.activityList reloadData];
  }];
}

- (void)hub:(DIYHarmonyHub *)hub currentActivityChangedOld:(nullable NSDictionary<NSString *, NSObject *> *)oldActivity {
  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
    [self.activityList reloadData];
  }];
}

- (void)hub:(DIYHarmonyHub *)hub devicesChangedOld:(nullable NSArray<NSDictionary<NSString *, NSObject *> *> *)oldDevices {
  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
    [self.deviceList reloadData];
  }];
}

@end
