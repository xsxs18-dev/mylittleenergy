#import <Foundation/Foundation.h>

// Everything MyLittleEnergy does inside SpringBoard: alerts, sounds, speech, the HUD,
// the charging animation, automation actions and keeping Low Power Mode on.
@interface VXSBController : NSObject
+ (instancetype)shared;
- (void)start;
- (BOOL)hidesNativeChargingView;
@end
