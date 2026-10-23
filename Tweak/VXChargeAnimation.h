#import <UIKit/UIKit.h>

enum {
	VXAnimationRing = 0,
	VXAnimationWave = 1,
	VXAnimationPulse = 2,
};

// Full screen charging animation shown when a charger is connected on the lock screen.
@interface VXChargeAnimation : NSObject
+ (void)showWithStyle:(NSInteger)style duration:(NSTimeInterval)duration details:(BOOL)details accent:(UIColor *)accent fahrenheit:(BOOL)fahrenheit;
+ (BOOL)isShowing;
@end
