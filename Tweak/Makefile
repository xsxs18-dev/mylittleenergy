include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MyLittleEnergy

MyLittleEnergy_FILES = Tweak.x VXLook.x VXSBController.m VXBanner.m VXHUD.m VXChargeAnimation.m VXActions.m VXWindow.m ../Shared/VXShared.m ../Shared/VXBattery.m
MyLittleEnergy_CFLAGS = -fobjc-arc -I../Shared -DVX_VERSION=\"$(VX_VERSION)\" -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-unknown-warning-option -Wno-unused-but-set-global
# AudioToolbox, AVFAudio and the private frameworks are opened at runtime in SpringBoard only.
MyLittleEnergy_FRAMEWORKS = UIKit Foundation QuartzCore


ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
MyLittleEnergy_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/tweak.mk
