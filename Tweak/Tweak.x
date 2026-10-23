#import "VXLook.h"
#import "VXSBController.h"
#import "VXShared.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#ifndef VX_VERSION
#define VX_VERSION "0"
#endif

@interface CSCoverSheetViewController : UIViewController
@end

// The lock screen's own charging view is skipped while MyLittleEnergy shows its animation.
%group CoverSheet

%hook CSCoverSheetViewController

- (void)_transitionChargingViewToVisible:(BOOL)visible showBattery:(BOOL)showBattery animated:(BOOL)animated {
	if (visible && [VXSBController.shared hidesNativeChargingView]) visible = NO;
	%orig(visible, showBattery, animated);
}

- (void)_transitionChargingViewToVisible:(BOOL)visible suppressedByPack:(BOOL)suppressed showBattery:(BOOL)showBattery animated:(BOOL)animated {
	if (visible && [VXSBController.shared hidesNativeChargingView]) visible = NO;
	%orig(visible, suppressed, showBattery, animated);
}

%end

%end

#define VX_LAUNCH_FLAG [VX_DIR stringByAppendingPathComponent:@"springboard-launch"]

#define VX_LAUNCH_ATTEMPTS 3

// The fuse counts starts that didn't stay up for 30 seconds. A single respring in that window
// (a second respring, Sileo installing something, another tweak crashing SpringBoard) is not a
// MyLittleEnergy failure, so only three interrupted starts in a row disable the integration. It then stays
// disabled across resprings and reboots until the app's Retry button or the next install clears it.
// Never kill SpringBoard ourselves: the system watchdog owns process recovery.
static BOOL VXSpringBoardShouldStart(void) {
	NSString *stored = [NSString stringWithContentsOfFile:VX_LAUNCH_FLAG encoding:NSUTF8StringEncoding error:nil];
	// An empty fuse file comes from versions that disabled after one interrupted start.
	NSInteger attempts = stored ? MAX(stored.integerValue, 1) : 0;
	if (attempts >= VX_LAUNCH_ATTEMPTS) {
		VXWritePlist(VX_SB_STATUS_PATH, @{ @"safeMode": @YES, @"time": @(NSDate.date.timeIntervalSince1970), @"version": @VX_VERSION });
		NSLog(@"[MyLittleEnergy] Initialization was interrupted %ld times in a row; SpringBoard integration remains disabled", (long)attempts);
		return NO;
	}
	VXEnsureDirectory();
	// If the fuse cannot be armed, skip integration rather than start unprotected.
	return [[NSString stringWithFormat:@"%ld", (long)(attempts + 1)] writeToFile:VX_LAUNCH_FLAG atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void VXStartSpringBoard(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		if (!VXSpringBoardShouldStart()) return;
		VXLookInit();
		[VXSBController.shared start];
		Class coverSheet = objc_getClass("CSCoverSheetViewController");
		if ([coverSheet instancesRespondToSelector:@selector(_transitionChargingViewToVisible:showBattery:animated:)]
			|| [coverSheet instancesRespondToSelector:@selector(_transitionChargingViewToVisible:suppressedByPack:showBattery:animated:)]) {
			%init(CoverSheet, CSCoverSheetViewController = coverSheet);
		}
		// Includes the controller's deferred initialization and multiple run-loop turns.
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			[NSFileManager.defaultManager removeItemAtPath:VX_LAUNCH_FLAG error:nil];
		});
	});
}

%ctor {
	@autoreleasepool {
		NSBundle *bundle = NSBundle.mainBundle;
		if (![bundle.bundlePath hasSuffix:@".app"]) return;
		if ([bundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
			// Do not read battery state, load private frameworks, or install UI hooks
			// from the dylib constructor while SpringBoard is still bootstrapping.
			[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ VXStartSpringBoard(); });
			}];
		} else {
			dispatch_async(dispatch_get_main_queue(), ^{ VXLookInit(); });
		}
	}
}
