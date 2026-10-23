#import "VXChargeAnimation.h"
#import "VXWindow.h"
#import "VXBattery.h"
#import "VXShared.h"

static VXWindow *gWindow;
static NSUInteger gGeneration;

#pragma mark - Wave view

@interface VXWaveView : UIView
@property (nonatomic) CGFloat level;
@property (nonatomic, strong) UIColor *color;
@end

@implementation VXWaveView {
	CADisplayLink *_link;
	CAShapeLayer *_back;
	CAShapeLayer *_front;
	CGFloat _phase;
	CGFloat _shown;
}

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		self.layer.cornerRadius = 34;
		self.layer.cornerCurve = kCACornerCurveContinuous;
		self.layer.borderWidth = 4;
		self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.85].CGColor;
		self.clipsToBounds = YES;
		_back = [CAShapeLayer layer];
		_front = [CAShapeLayer layer];
		[self.layer addSublayer:_back];
		[self.layer addSublayer:_front];
	}
	return self;
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	[_link invalidate];
	_link = nil;
	if (!self.window) return;
	_link = [CADisplayLink displayLinkWithTarget:self selector:@selector(step)];
	[_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (UIBezierPath *)waveWithOffset:(CGFloat)offset amplitude:(CGFloat)amplitude {
	CGSize size = self.bounds.size;
	CGFloat top = size.height * (1 - _shown);
	UIBezierPath *path = [UIBezierPath bezierPath];
	[path moveToPoint:CGPointMake(0, size.height)];
	for (CGFloat x = 0; x <= size.width; x += 4) {
		CGFloat y = top + sin(x / size.width * 2 * M_PI + _phase + offset) * amplitude;
		[path addLineToPoint:CGPointMake(x, y)];
	}
	[path addLineToPoint:CGPointMake(size.width, size.height)];
	[path closePath];
	return path;
}

- (void)step {
	// The display link keeps this view alive, so it stops itself once the window is gone.
	if (!self.window || self.window.hidden) {
		[_link invalidate];
		_link = nil;
		return;
	}
	_phase += 0.07;
	_shown += (_level - _shown) * 0.04;
	CGFloat amplitude = _shown > 0.97 ? 2 : 7;
	_back.fillColor = [_color colorWithAlphaComponent:0.45].CGColor;
	_front.fillColor = _color.CGColor;
	_back.path = [self waveWithOffset:M_PI amplitude:amplitude].CGPath;
	_front.path = [self waveWithOffset:0 amplitude:amplitude].CGPath;
}

@end

#pragma mark - Animation

@implementation VXChargeAnimation

+ (BOOL)isShowing {
	return gWindow && !gWindow.hidden;
}

+ (UIColor *)colorForLevel:(NSInteger)level accent:(UIColor *)accent {
	if (level <= 20) return UIColor.systemRedColor;
	if (level <= 40) return UIColor.systemOrangeColor;
	return accent ?: UIColor.systemGreenColor;
}

+ (NSString *)detailsFor:(VXBatteryInfo *)info fahrenheit:(BOOL)fahrenheit {
	NSMutableArray *parts = [NSMutableArray array];
	double watts = info.batteryPower > 0.05 ? info.batteryPower : info.adapterWatts;
	if (watts > 0.05) [parts addObject:[NSString stringWithFormat:@"%.1f W", watts]];
	// Time to the limit (or to full) as estimated by the service.
	VXLive live = VXLiveUnpack(VXGetState(VX_NOTIFY_LIVE));
	if (info.charging && live.valid && live.minutes >= 0) {
		NSString *time = [NSString stringWithFormat:@"%ld:%02ld", (long)(live.minutes / 60), (long)(live.minutes % 60)];
		NSInteger target = [VXReadPlist(VX_STATUS_PATH)[@"chargeTarget"] integerValue];
		[parts addObject:target > 0 && target < 100 ? [NSString stringWithFormat:VXL(@"%ld%% in %@"), (long)target, time] : [NSString stringWithFormat:VXL(@"Full in %@"), time]];
	}
	if (!isnan(info.temperature)) {
		[parts addObject:fahrenheit ? [NSString stringWithFormat:@"%.0f °F", info.temperature * 9 / 5 + 32] : [NSString stringWithFormat:@"%.0f °C", info.temperature]];
	}
	return [parts componentsJoinedByString:@"  ·  "];
}

+ (void)showWithStyle:(NSInteger)style duration:(NSTimeInterval)duration details:(BOOL)details accent:(UIColor *)accent fahrenheit:(BOOL)fahrenheit {
	VXBatteryInfo *info = [VXBatteryInfo current];
	NSInteger level = info ? info.level : 0;
	UIColor *color = [self colorForLevel:level accent:accent];

	gWindow.hidden = YES;
	VXWindow *window = [VXWindow overlayWithLevel:UIWindowLevelStatusBar + 100];
	gWindow = window;
	NSUInteger generation = ++gGeneration;
	UIView *root = window.rootViewController.view;
	CGRect bounds = window.bounds;
	CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds) - 40);

	UIView *dim = [[UIView alloc] initWithFrame:bounds];
	dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.62];
	dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[root addSubview:dim];

	UIView *stage = [[UIView alloc] initWithFrame:bounds];
	stage.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[root addSubview:stage];

	UILabel *percent = [UILabel new];
	percent.textColor = UIColor.whiteColor;
	percent.textAlignment = NSTextAlignmentCenter;
	UIFontDescriptor *rounded = [[UIFont systemFontOfSize:56 weight:UIFontWeightBold].fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
	percent.font = rounded ? [UIFont fontWithDescriptor:rounded size:56] : [UIFont systemFontOfSize:56 weight:UIFontWeightBold];
	percent.text = [NSString stringWithFormat:@"%ld%%", (long)level];
	[percent sizeToFit];

	UILabel *subtitle = [UILabel new];
	subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.8];
	subtitle.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium];
	subtitle.textAlignment = NSTextAlignmentCenter;
	subtitle.text = details && info ? [self detailsFor:info fahrenheit:fahrenheit] : VXL(@"Charging");
	subtitle.frame = CGRectMake(20, 0, bounds.size.width - 40, 24);

	if (style == VXAnimationWave) {
		VXWaveView *wave = [[VXWaveView alloc] initWithFrame:CGRectMake(0, 0, 150, 260)];
		wave.center = center;
		wave.color = color;
		wave.level = level / 100.0;
		[stage addSubview:wave];
		UIView *pin = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 54, 12)];
		pin.backgroundColor = [UIColor colorWithWhite:1 alpha:0.85];
		pin.layer.cornerRadius = 5;
		pin.center = CGPointMake(center.x, CGRectGetMinY(wave.frame) - 9);
		[stage addSubview:pin];
		percent.center = center;
		subtitle.center = CGPointMake(center.x, CGRectGetMaxY(wave.frame) + 36);
	} else if (style == VXAnimationPulse) {
		UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:120 weight:UIImageSymbolWeightBold];
		UIImageView *bolt = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bolt.fill" withConfiguration:configuration]];
		bolt.tintColor = color;
		[bolt sizeToFit];
		bolt.center = CGPointMake(center.x, center.y - 40);
		bolt.layer.shadowColor = color.CGColor;
		bolt.layer.shadowRadius = 28;
		bolt.layer.shadowOpacity = 0.9;
		bolt.layer.shadowOffset = CGSizeZero;
		[stage addSubview:bolt];
		CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
		pulse.fromValue = @0.88;
		pulse.toValue = @1.08;
		pulse.duration = 0.8;
		pulse.autoreverses = YES;
		pulse.repeatCount = HUGE_VALF;
		pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
		[bolt.layer addAnimation:pulse forKey:@"pulse"];
		percent.center = CGPointMake(center.x, CGRectGetMaxY(bolt.frame) + 50);
		subtitle.center = CGPointMake(center.x, CGRectGetMaxY(percent.frame) + 22);
	} else {
		CGFloat radius = 110;
		UIBezierPath *circle = [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
		CAShapeLayer *track = [CAShapeLayer layer];
		track.path = circle.CGPath;
		track.fillColor = UIColor.clearColor.CGColor;
		track.strokeColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
		track.lineWidth = 18;
		[stage.layer addSublayer:track];

		CAShapeLayer *progress = [CAShapeLayer layer];
		progress.path = circle.CGPath;
		progress.fillColor = UIColor.clearColor.CGColor;
		progress.strokeColor = UIColor.blackColor.CGColor;
		progress.lineWidth = 18;
		progress.lineCap = kCALineCapRound;
		progress.strokeEnd = MAX(level / 100.0, 0.01);
		CAGradientLayer *gradient = [CAGradientLayer layer];
		gradient.frame = bounds;
		gradient.colors = @[(id)[color colorWithAlphaComponent:0.55].CGColor, (id)color.CGColor];
		gradient.startPoint = CGPointMake(0, 1);
		gradient.endPoint = CGPointMake(1, 0);
		gradient.mask = progress;
		gradient.shadowColor = color.CGColor;
		[stage.layer addSublayer:gradient];
		CABasicAnimation *fill = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
		fill.fromValue = @0;
		fill.toValue = @(progress.strokeEnd);
		fill.duration = 1.2;
		fill.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.2 :0.8 :0.2 :1];
		[progress addAnimation:fill forKey:@"fill"];

		UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightBold];
		UIImageView *bolt = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bolt.fill" withConfiguration:configuration]];
		bolt.tintColor = color;
		[bolt sizeToFit];
		bolt.center = CGPointMake(center.x, center.y - 46);
		[stage addSubview:bolt];
		percent.center = CGPointMake(center.x, center.y + 4);
		subtitle.center = CGPointMake(center.x, center.y + radius + 46);
	}
	[stage addSubview:percent];
	[stage addSubview:subtitle];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissTapped)];
	[root addGestureRecognizer:tap];

	window.hidden = NO;
	dim.alpha = 0;
	stage.alpha = 0;
	stage.transform = CGAffineTransformMakeScale(0.85, 0.85);
	[UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.3 options:0 animations:^{
		dim.alpha = 1;
		stage.alpha = 1;
		stage.transform = CGAffineTransformIdentity;
	} completion:nil];

	// Charger details (watts, time to full) usually show up a second after plugging in.
	if (details) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if (generation != gGeneration) return;
			VXBatteryInfo *later = [VXBatteryInfo current];
			if (!later) return;
			NSString *text = [self detailsFor:later fahrenheit:fahrenheit];
			if (text.length) subtitle.text = text;
			percent.text = [NSString stringWithFormat:@"%ld%%", (long)later.level];
		});
	}
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(duration, 1.5) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (generation == gGeneration) [self dismiss];
	});
}

+ (void)dismissTapped {
	[self dismiss];
}

+ (void)dismiss {
	VXWindow *window = gWindow;
	if (!window) return;
	NSUInteger generation = gGeneration;
	[UIView animateWithDuration:0.35 animations:^{
		window.rootViewController.view.alpha = 0;
	} completion:^(BOOL finished) {
		window.hidden = YES;
		if (generation == gGeneration) gWindow = nil;
	}];
}

@end
