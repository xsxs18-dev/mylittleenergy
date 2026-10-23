#import "VXBanner.h"
#import "VXWindow.h"

static VXWindow *gWindow;
static NSUInteger gGeneration;

@implementation VXBanner

+ (void)showTitle:(NSString *)title text:(NSString *)text symbol:(NSString *)symbol color:(UIColor *)color {
	if (!NSThread.isMainThread) {
		dispatch_async(dispatch_get_main_queue(), ^{ [self showTitle:title text:text symbol:symbol color:color]; });
		return;
	}
	gWindow.hidden = YES;
	VXWindow *window = [VXWindow overlayWithLevel:UIWindowLevelStatusBar + 1000];
	window.passesAllTouches = YES;
	gWindow = window;
	NSUInteger generation = ++gGeneration;

	UIVisualEffectView *pill = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
	pill.translatesAutoresizingMaskIntoConstraints = NO;
	pill.layer.cornerRadius = 24;
	pill.layer.cornerCurve = kCACornerCurveContinuous;
	pill.clipsToBounds = YES;

	UIView *badge = [UIView new];
	badge.translatesAutoresizingMaskIntoConstraints = NO;
	badge.backgroundColor = color ?: UIColor.systemGreenColor;
	badge.layer.cornerRadius = 15;
	badge.layer.cornerCurve = kCACornerCurveContinuous;
	UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
	UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol ?: @"bolt.fill" withConfiguration:configuration]];
	icon.translatesAutoresizingMaskIntoConstraints = NO;
	icon.tintColor = UIColor.whiteColor;
	icon.contentMode = UIViewContentModeCenter;
	[badge addSubview:icon];

	UILabel *titleLabel = [UILabel new];
	titleLabel.text = title;
	titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	UILabel *textLabel = [UILabel new];
	textLabel.text = text;
	textLabel.font = [UIFont systemFontOfSize:13];
	textLabel.textColor = UIColor.secondaryLabelColor;
	textLabel.numberOfLines = 2;
	textLabel.hidden = text.length == 0;
	UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, textLabel]];
	labels.axis = UILayoutConstraintAxisVertical;
	labels.spacing = 1;
	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[badge, labels]];
	row.spacing = 11;
	row.alignment = UIStackViewAlignmentCenter;
	row.translatesAutoresizingMaskIntoConstraints = NO;
	[pill.contentView addSubview:row];

	UIView *root = window.rootViewController.view;
	[root addSubview:pill];
	[NSLayoutConstraint activateConstraints:@[
		[badge.widthAnchor constraintEqualToConstant:30],
		[badge.heightAnchor constraintEqualToConstant:30],
		[icon.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
		[icon.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
		[row.leadingAnchor constraintEqualToAnchor:pill.contentView.leadingAnchor constant:10],
		[row.trailingAnchor constraintEqualToAnchor:pill.contentView.trailingAnchor constant:-18],
		[row.topAnchor constraintEqualToAnchor:pill.contentView.topAnchor constant:9],
		[row.bottomAnchor constraintEqualToAnchor:pill.contentView.bottomAnchor constant:-9],
		[pill.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
		[pill.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor constant:6],
		[pill.widthAnchor constraintLessThanOrEqualToAnchor:root.widthAnchor constant:-32],
	]];

	window.hidden = NO;
	pill.alpha = 0;
	pill.transform = CGAffineTransformMakeTranslation(0, -40);
	[UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.6 options:0 animations:^{
		pill.alpha = 1;
		pill.transform = CGAffineTransformIdentity;
	} completion:nil];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (generation != gGeneration) return;
		[UIView animateWithDuration:0.3 animations:^{
			pill.alpha = 0;
			pill.transform = CGAffineTransformMakeTranslation(0, -40);
		} completion:^(BOOL finished) {
			if (generation != gGeneration) return;
			gWindow.hidden = YES;
			gWindow = nil;
		}];
	});
}

@end
