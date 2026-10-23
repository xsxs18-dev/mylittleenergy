#import <Foundation/Foundation.h>

// System switches the automation rules can flip. Runs in SpringBoard; every
// private API is looked up at runtime, a missing one only disables that action.
@interface VXActions : NSObject
+ (instancetype)shared;
- (void)perform:(NSInteger)action value:(NSInteger)value;
- (BOOL)canPerform:(NSInteger)action;
// Off the main thread, a moment from now (iOS needs to finish turning it off first).
- (void)turnOnLowPowerSoon;
@end
