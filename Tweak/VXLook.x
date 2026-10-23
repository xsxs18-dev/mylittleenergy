// Battery icon colors and the status bar text. Runs in every UIKit process,
// sandboxed apps included, so all values come from notify states.
#import "VXShared.h"
#import "VXLook.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface _UIBatteryView : UIView
@property (nonatomic) double chargePercent;
@property (nonatomic) long long chargingState;
@property (nonatomic) bool saverModeActive;
@property (nonatomic, copy) UIColor *fillColor;
@property (getter=isLowBattery, nonatomic, readonly) bool lowBattery;
- (void)_updateFillColor;
@end

@interface _UIStatusBarStringView : UILabel
@end

@interface _UIStatusBarTimeItem : NSObject
@end

static VXLook gLook;
static VXLive gLive;
static UIColor *gIconColor;
static UIColor *gChargingColor;
static NSHashTable<_UIBatteryView *> *gBatteryViews;
static NSHashTable<UILabel *> *gTimeViews;
static char kVXTimeView;
static char kVXOriginalText;
static char kVXComposed;
static char kVXComposing;

static UIColor *VXColorFromRGB(uint32_t rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

#pragma mark - Battery icon

// chargingState 0 is unplugged and 4 is plugged in without charging; everything else is charging.
static BOOL VXIsCharging(_UIBatteryView *view) {
	long long state = view.chargingState;
	return state != 0 && state != 4;
}

static UIColor *VXFillColor(_UIBatteryView *view) {
	if (!gLook.enabled) return nil;
	BOOL customizing = gLook.iconMode != VXIconSystem || gLook.iconChargingCustom || (gLook.iconLowThreshold != 20 && gLook.iconLowThreshold > 0);
	if (!customizing) return nil;
	BOOL charging = VXIsCharging(view);
	if (charging) return gLook.iconChargingCustom ? gChargingColor : nil;
	if (view.saverModeActive) return nil;
	double level = MAX(0, MIN(1, view.chargePercent));
	if (gLook.iconLowThreshold > 0 && level * 100 <= gLook.iconLowThreshold) return UIColor.systemRedColor;
	switch (gLook.iconMode) {
		case VXIconCustom: return gIconColor;
		case VXIconByLevel: return [UIColor colorWithHue:0.33 * level saturation:0.82 brightness:0.92 alpha:1];
	}
	// System colors with a lower red threshold: where iOS would already turn the icon red at its own
	// 20 %, keep the normal fill. Everywhere else the system color is right.
	if ([view respondsToSelector:@selector(isLowBattery)] && view.isLowBattery) return view.fillColor;
	return nil;
}

%hook _UIBatteryView

- (UIColor *)_batteryFillColor {
	if (!NSThread.isMainThread) return %orig;
	[gBatteryViews addObject:self];
	UIColor *color = VXFillColor(self);
	return color ?: %orig;
}

%end

#pragma mark - Status bar

static UIFont *VXInfoFont(UIFont *base, CGFloat scale) {
	UIFont *font = [UIFont monospacedDigitSystemFontOfSize:MAX(base.pointSize * scale, 8) weight:UIFontWeightSemibold];
	return font;
}

static void VXCompose(UILabel *label, NSString *time) {
	NSString *separator = gLook.statusBarMode == VXStatusBarAppend ? @" " : @" · ";
	NSString *info = time ? VXStatusBarText(gLook, gLive, separator) : nil;
	if (!info) {
		if (objc_getAssociatedObject(label, &kVXComposed)) {
			objc_setAssociatedObject(label, &kVXComposed, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			label.numberOfLines = 1;
		}
		return;
	}
	UIFont *font = label.font ?: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
	UIColor *color = label.textColor ?: UIColor.labelColor;
	NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
	paragraph.alignment = label.textAlignment;
	NSMutableAttributedString *text = [NSMutableAttributedString new];
	switch (gLook.statusBarMode) {
		case VXStatusBarTwoLines: {
			paragraph.alignment = NSTextAlignmentCenter;
			paragraph.lineHeightMultiple = 0.82;
			UIFont *timeFont = [font fontWithSize:font.pointSize * 0.74];
			[text appendAttributedString:[[NSAttributedString alloc] initWithString:time attributes:@{NSFontAttributeName: timeFont, NSForegroundColorAttributeName: color}]];
			[text appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\n" stringByAppendingString:info] attributes:@{NSFontAttributeName: VXInfoFont(font, 0.52), NSForegroundColorAttributeName: color}]];
			label.numberOfLines = 2;
			break;
		}
		case VXStatusBarReplace:
			[text appendAttributedString:[[NSAttributedString alloc] initWithString:info attributes:@{NSFontAttributeName: VXInfoFont(font, 0.8), NSForegroundColorAttributeName: color}]];
			label.numberOfLines = 1;
			break;
		default:
			[text appendAttributedString:[[NSAttributedString alloc] initWithString:time attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color}]];
			[text appendAttributedString:[[NSAttributedString alloc] initWithString:[@" " stringByAppendingString:info] attributes:@{NSFontAttributeName: VXInfoFont(font, 0.68), NSForegroundColorAttributeName: color}]];
			label.numberOfLines = 1;
			break;
	}
	[text addAttribute:NSParagraphStyleAttributeName value:paragraph range:NSMakeRange(0, text.length)];
	objc_setAssociatedObject(label, &kVXComposed, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	label.attributedText = text;
}

static void VXRefreshTimeView(UILabel *label) {
	NSString *original = objc_getAssociatedObject(label, &kVXOriginalText);
	if (!original) return;
	// Goes through the setText: hook, which stores the time again and composes the label.
	label.text = original;
}

static void VXMarkTimeView(UILabel *label) {
	if (!NSThread.isMainThread || ![label isKindOfClass:[UILabel class]] || objc_getAssociatedObject(label, &kVXTimeView)) return;
	objc_setAssociatedObject(label, &kVXTimeView, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[gTimeViews addObject:label];
	if (!label.text.length) return;
	objc_setAssociatedObject(label, &kVXOriginalText, label.text, OBJC_ASSOCIATION_COPY_NONATOMIC);
	// With the status bar module off the label is only remembered, never touched.
	if (gLook.enabled && gLook.statusBarMode != VXStatusBarOff) VXRefreshTimeView(label);
}

%hook _UIStatusBarTimeItem

- (id)applyUpdate:(id)update toDisplayItem:(id)item {
	id result = %orig;
	for (NSString *key in @[@"shortTimeView", @"pillTimeView", @"timeView"]) {
		if (![self respondsToSelector:NSSelectorFromString(key)]) continue;
		VXMarkTimeView([self valueForKey:key]);
	}
	return result;
}

%end

%hook _UIStatusBarStringView

- (void)setText:(NSString *)text {
	if (!NSThread.isMainThread || !objc_getAssociatedObject(self, &kVXTimeView) || objc_getAssociatedObject(self, &kVXComposing)) {
		%orig;
		return;
	}
	objc_setAssociatedObject(self, &kVXOriginalText, text, OBJC_ASSOCIATION_COPY_NONATOMIC);
	// UIKit may route attributedText through setText:. Keep nested setter calls
	// from composing again or overwriting the saved system time.
	objc_setAssociatedObject(self, &kVXComposing, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	@try {
		%orig;
		VXCompose(self, text);
	} @finally {
		objc_setAssociatedObject(self, &kVXComposing, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
}

%end

#pragma mark - Updates

static void VXRefreshAll(BOOL timeViews, BOOL batteryViews) {
	if (timeViews) for (UILabel *label in gTimeViews.allObjects) VXRefreshTimeView(label);
	if (batteryViews) {
		for (_UIBatteryView *view in gBatteryViews.allObjects) {
			if ([view respondsToSelector:@selector(_updateFillColor)]) [view _updateFillColor];
		}
	}
}

static void VXReadColors(uint64_t state) {
	gIconColor = VXColorFromRGB(state & 0xFFFFFF);
	gChargingColor = VXColorFromRGB((state >> 24) & 0xFFFFFF);
}

void VXLookInit(void) {
	static BOOL initialized;
	if (initialized || !NSThread.isMainThread) return;
	initialized = YES;
	gBatteryViews = [NSHashTable weakObjectsHashTable];
	gTimeViews = [NSHashTable weakObjectsHashTable];
	gLook = VXLookUnpack(VXGetState(VX_NOTIFY_LOOK));
	gLive = VXLiveUnpack(VXGetState(VX_NOTIFY_LIVE));
	VXReadColors(VXGetState(VX_NOTIFY_COLORS));

	VXObserve(VX_NOTIFY_LIVE, ^(uint64_t state) {
		VXLive live = VXLiveUnpack(state);
		BOOL chargingChanged = live.charging != gLive.charging || live.external != gLive.external;
		gLive = live;
		BOOL statusBar = gLook.enabled && gLook.statusBarMode != VXStatusBarOff;
		VXRefreshAll(statusBar, chargingChanged);
	});
	VXObserve(VX_NOTIFY_LOOK, ^(uint64_t state) {
		gLook = VXLookUnpack(state);
		VXRefreshAll(YES, YES);
	});
	VXObserve(VX_NOTIFY_COLORS, ^(uint64_t state) {
		VXReadColors(state);
		VXRefreshAll(NO, YES);
	});
	%init;
}
