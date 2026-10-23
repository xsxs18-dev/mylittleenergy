#import <UIKit/UIKit.h>

// Small floating battery readout above every app. Drag to move, tap to open
// MyLittleEnergy, long press to switch between the compact and the large layout.
@interface VXHUD : NSObject
+ (instancetype)shared;
- (void)updateWithSettings:(NSDictionary *)settings locked:(BOOL)locked plugged:(BOOL)plugged;
@end
