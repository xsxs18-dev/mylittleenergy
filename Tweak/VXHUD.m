#import "VXHUD.h"
#import "VXWindow.h"
#import "VXBattery.h"
#import "VXShared.h"
#import <objc/message.h>

@implementation VXHUD {
	VXWindow *_window;
	UIVisualEffectView *_pill;
	UILabel *_topLabel;
	UILabel *_bottomLabel;
	UIImageView *_bolt;
	NSTimer *_timer;
	NSDictionary *_settings;
	NSMutableDictionary *_state;
	CGPoint _panStart;
}

+ (instancetype)shared {
	static VXHUD *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [VXHUD new]; });
	return shared;
}

- (instancetype)init {
	if ((self = [super init])) {
		_state = [VXReadPlist(VX_HUD_PATH) mutableCopy] ?: [NSMutableDictionary dictionary];
	}
	return self;
}

- (BOOL)large {
	id size = _state[@"size"] ?: _settings[@"hudSize"];
	return [size integerValue] == 1;
}

- (void)updateWithSettings:(NSDictionary *)settings locked:(BOOL)locked plugged:(BOOL)plugged {
	// A new size in the app wins over the last long press; "Reset Position" in the app deletes hud.plist.
	if (_settings && ![_settings[@"hudSize"] isEqual:settings[@"hudSize"]]) [_state removeObjectForKey:@"size"];
	if (![NSFileManager.defaultManager fileExistsAtPath:VX_HUD_PATH]) [_state removeAllObjects];
	_settings = settings;
	BOOL visible = VXSettingBool(settings, @"enabled") && VXSettingBool(settings, @"hudEnabled")
		&& (VXSettingInt(settings, @"hudWhen") == 0 || plugged)
		&& !(locked && VXSettingBool(settings, @"hudHideLock"));
	if (visible) [self show];
	else [self hide];
}

#pragma mark - Window

- (void)show {
	if (!_window) [self build];
	_pill.alpha = MAX(0.3, MIN(1, VXSettingDouble(_settings, @"hudOpacity")));
	[self applyLayout];
	if (_window.hidden) {
		_window.hidden = NO;
		_pill.transform = CGAffineTransformMakeScale(0.6, 0.6);
		[UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.4 options:0 animations:^{
			self->_pill.transform = CGAffineTransformIdentity;
		} completion:nil];
	}
	[self refresh];
	if (!_timer) {
		_timer = [NSTimer timerWithTimeInterval:2 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
		_timer.tolerance = 0.5;
		[NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
	}
}

- (void)hide {
	[_timer invalidate];
	_timer = nil;
	_window.hidden = YES;
}

- (void)build {
	_window = [VXWindow overlayWithLevel:UIWindowLevelStatusBar + 20];
	UIView *root = _window.rootViewController.view;

	_pill = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
	_pill.layer.cornerCurve = kCACornerCurveContinuous;
	_pill.clipsToBounds = YES;
	_pill.layer.borderWidth = 0.5;
	_pill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
	[root addSubview:_pill];
	_window.touchView = _pill;

	_bolt = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bolt.fill"]];
	_bolt.tintColor = UIColor.systemYellowColor;
	_bolt.contentMode = UIViewContentModeScaleAspectFit;
	_topLabel = [UILabel new];
	_topLabel.textColor = UIColor.whiteColor;
	_bottomLabel = [UILabel new];
	_bottomLabel.textColor = [UIColor colorWithWhite:1 alpha:0.75];
	for (UIView *view in @[_bolt, _topLabel, _bottomLabel]) [_pill.contentView addSubview:view];

	[_pill addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
	[_pill addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap)]];
	UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(press:)];
	press.minimumPressDuration = 0.5;
	[_pill addGestureRecognizer:press];
}

- (void)applyLayout {
	BOOL large = [self large];
	_topLabel.font = large ? [UIFont monospacedDigitSystemFontOfSize:22 weight:UIFontWeightBold] : [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
	_bottomLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
	_bottomLabel.hidden = !large;
}

- (void)layout {
	BOOL large = [self large];
	[_topLabel sizeToFit];
	[_bottomLabel sizeToFit];
	CGFloat boltSize = large ? 18 : 12;
	CGFloat boltWidth = _bolt.hidden ? 0 : boltSize + 4;
	CGFloat width, height;
	if (large) {
		width = MAX(_topLabel.bounds.size.width + boltWidth, _bottomLabel.bounds.size.width) + 28;
		height = _topLabel.bounds.size.height + _bottomLabel.bounds.size.height + 18;
		_bolt.frame = CGRectMake(14, 9 + (_topLabel.bounds.size.height - boltSize) / 2, boltSize, boltSize);
		_topLabel.frame = CGRectMake(14 + boltWidth, 9, _topLabel.bounds.size.width, _topLabel.bounds.size.height);
		_bottomLabel.frame = CGRectMake(14, CGRectGetMaxY(_topLabel.frame), _bottomLabel.bounds.size.width, _bottomLabel.bounds.size.height);
	} else {
		width = _topLabel.bounds.size.width + boltWidth + 22;
		height = MAX(_topLabel.bounds.size.height, boltSize) + 12;
		_bolt.frame = CGRectMake(11, (height - boltSize) / 2, boltSize, boltSize);
		_topLabel.frame = CGRectMake(11 + boltWidth, (height - _topLabel.bounds.size.height) / 2, _topLabel.bounds.size.width, _topLabel.bounds.size.height);
	}
	_pill.layer.cornerRadius = large ? 18 : height / 2;
	CGRect bounds = _window.bounds;
	CGFloat x = _state[@"x"] ? [_state[@"x"] doubleValue] : 0.8;
	CGFloat y = _state[@"y"] ? [_state[@"y"] doubleValue] : 0.1;
	_pill.bounds = CGRectMake(0, 0, ceil(width), ceil(height));
	_pill.center = [self clamp:CGPointMake(x * bounds.size.width, y * bounds.size.height)];
}

- (CGPoint)clamp:(CGPoint)point {
	CGRect area = UIEdgeInsetsInsetRect(_window.bounds, _window.safeAreaInsets);
	CGSize size = _pill.bounds.size;
	point.x = MIN(MAX(point.x, CGRectGetMinX(area) + size.width / 2 + 4), CGRectGetMaxX(area) - size.width / 2 - 4);
	point.y = MIN(MAX(point.y, CGRectGetMinY(area) + size.height / 2), CGRectGetMaxY(area) - size.height / 2 - 4);
	return point;
}

#pragma mark - Content

- (void)refresh {
	VXBatteryInfo *info = [VXBatteryInfo current];
	if (!info) return;
	NSInteger fields = VXSettingInt(_settings, @"hudFields");
	BOOL fahrenheit = VXSettingInt(_settings, @"tempUnit") == 1;
	NSMutableArray *parts = [NSMutableArray array];
	NSString *percent = [NSString stringWithFormat:@"%ld%%", (long)info.level];
	NSString *power = [NSString stringWithFormat:@"%@%.1f W", info.batteryPower < -0.05 ? @"−" : @"", fabs(info.batteryPower)];
	NSString *temperature = isnan(info.temperature) ? nil : (fahrenheit ? [NSString stringWithFormat:@"%.1f °F", info.temperature * 9 / 5 + 32] : [NSString stringWithFormat:@"%.1f °C", info.temperature]);
	// The service's estimate (from the recent drain), the same one the status bar and widgets show.
	VXLive live = VXLiveUnpack(VXGetState(VX_NOTIFY_LIVE));
	NSInteger minutes = live.valid ? live.minutes : -1;
	NSString *time = minutes >= 0 ? [NSString stringWithFormat:@"%ld:%02ld", (long)(minutes / 60), (long)(minutes % 60)] : nil;

	if ([self large]) {
		_topLabel.text = percent;
		if (fields & VXFieldPower) [parts addObject:power];
		if ((fields & VXFieldTemperature) && temperature) [parts addObject:temperature];
		if ((fields & VXFieldTime) && time) [parts addObject:time];
		if ((fields & VXFieldAdapter) && info.adapterWatts > 0) [parts addObject:[NSString stringWithFormat:@"%.0f W in", info.adapterWatts]];
		if ((fields & VXFieldHealth) && !isnan(info.health)) [parts addObject:[NSString stringWithFormat:@"♥︎ %.0f%%", info.health]];
		_bottomLabel.text = parts.count ? [parts componentsJoinedByString:@"  ·  "] : @" ";
	} else {
		if (fields & VXFieldPercent) [parts addObject:percent];
		if (fields & VXFieldPower) [parts addObject:power];
		if ((fields & VXFieldTemperature) && temperature) [parts addObject:temperature];
		if ((fields & VXFieldTime) && time) [parts addObject:time];
		if ((fields & VXFieldAdapter) && info.adapterWatts > 0) [parts addObject:[NSString stringWithFormat:@"%.0f W in", info.adapterWatts]];
		if ((fields & VXFieldHealth) && !isnan(info.health)) [parts addObject:[NSString stringWithFormat:@"♥︎ %.0f%%", info.health]];
		_topLabel.text = parts.count ? [parts componentsJoinedByString:@"  "] : percent;
	}
	_bolt.hidden = !info.plugged;
	_bolt.tintColor = info.charging ? UIColor.systemYellowColor : UIColor.systemGrayColor;
	[self layout];
}

#pragma mark - Gestures

- (void)pan:(UIPanGestureRecognizer *)gesture {
	if (gesture.state == UIGestureRecognizerStateBegan) _panStart = _pill.center;
	CGPoint translation = [gesture translationInView:_window];
	_pill.center = [self clamp:CGPointMake(_panStart.x + translation.x, _panStart.y + translation.y)];
	if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
		CGSize size = _window.bounds.size;
		_state[@"x"] = @(_pill.center.x / size.width);
		_state[@"y"] = @(_pill.center.y / size.height);
		VXWritePlist(VX_HUD_PATH, _state);
	}
}

- (void)tap {
	Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
	id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, NSSelectorFromString(@"defaultWorkspace"));
	SEL open = NSSelectorFromString(@"openApplicationWithBundleID:");
	if ([workspace respondsToSelector:open]) ((BOOL (*)(id, SEL, NSString *))objc_msgSend)(workspace, open, VX_BUNDLE_ID);
}

- (void)press:(UILongPressGestureRecognizer *)gesture {
	if (gesture.state != UIGestureRecognizerStateBegan) return;
	_state[@"size"] = @([self large] ? 0 : 1);
	VXWritePlist(VX_HUD_PATH, _state);
	UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
	[feedback impactOccurred];
	[UIView animateWithDuration:0.25 animations:^{
		[self applyLayout];
		[self refresh];
	}];
}

@end
