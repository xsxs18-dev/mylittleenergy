#import "VXWindow.h"

UIWindowScene *VXMainScene(void) {
	UIWindowScene *fallback = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) continue;
		if (scene.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)scene;
		if (!fallback) fallback = (UIWindowScene *)scene;
	}
	return fallback;
}

@implementation VXWindow

+ (instancetype)overlayWithLevel:(UIWindowLevel)level {
	UIWindowScene *scene = VXMainScene();
	VXWindow *window = scene ? [[self alloc] initWithWindowScene:scene] : [[self alloc] initWithFrame:UIScreen.mainScreen.bounds];
	window.windowLevel = level;
	window.backgroundColor = UIColor.clearColor;
	UIViewController *controller = [UIViewController new];
	controller.view.backgroundColor = UIColor.clearColor;
	window.rootViewController = controller;
	return window;
}

// Secure contexts are drawn above the lock screen and over apps.
- (BOOL)_shouldCreateContextAsSecure {
	return YES;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
	if (self.passesAllTouches) return nil;
	UIView *hit = [super hitTest:point withEvent:event];
	if (self.touchView) return [hit isDescendantOfView:self.touchView] ? hit : nil;
	return hit == self || hit == self.rootViewController.view ? nil : hit;
}

@end
