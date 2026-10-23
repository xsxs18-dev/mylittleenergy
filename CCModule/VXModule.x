// Control Center toggle for the charge limit. Loaded by CCSupport.
#import "VXShared.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface CCUIToggleModule : NSObject
- (void)refreshState;
@end

@interface VXLimitModule : CCUIToggleModule
@end

%subclass VXLimitModule : CCUIToggleModule

- (UIImage *)iconGlyph {
	UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
	return [UIImage systemImageNamed:@"bolt.batteryblock.fill" withConfiguration:configuration] ?: [UIImage systemImageNamed:@"bolt.fill" withConfiguration:configuration];
}

- (UIColor *)selectedColor {
	int32_t rgb = VXParseHexColor(VXReadSettings()[@"accentColor"]);
	if (rgb < 0) return UIColor.systemGreenColor;
	return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

- (BOOL)isSelected {
	return VXSettingBool(VXReadSettings(), @"limitEnabled");
}

- (void)setSelected:(BOOL)selected {
	NSMutableDictionary *settings = [VXReadSettings() mutableCopy];
	settings[@"limitEnabled"] = @(selected);
	VXWriteSettings(settings);
	if ([self respondsToSelector:@selector(refreshState)]) [self refreshState];
}

%end

%ctor {
	if (objc_getClass("CCUIToggleModule")) %init;
}
