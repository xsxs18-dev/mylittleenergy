#import <Foundation/Foundation.h>

// The daemon's brain: samples the battery, holds the charge limit, writes the
// history and tells SpringBoard about alerts and automation actions.
@interface VXEngine : NSObject
+ (instancetype)shared;
- (void)start;
// Gives charging back to iOS before the daemon exits.
- (void)shutdown;
@end
