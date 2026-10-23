#import <UIKit/UIKit.h>

UIWindowScene *VXMainScene(void);

// SpringBoard overlay window that also shows above the lock screen.
// Touches outside touchView go to whatever is below.
@interface VXWindow : UIWindow
@property (nonatomic, weak) UIView *touchView;
@property (nonatomic) BOOL passesAllTouches;
+ (instancetype)overlayWithLevel:(UIWindowLevel)level;
@end
