ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = MyLittleEnergy

MyLittleEnergy_FILES = $(wildcard Sources/*.swift) ../Shared/VXShared.m ../Shared/VXBattery.m
MyLittleEnergy_CFLAGS = -fobjc-arc -I../Shared -Wno-deprecated-declarations
MyLittleEnergy_SWIFT_BRIDGING_HEADER = MyLittleEnergy-Bridging-Header.h
MyLittleEnergy_FRAMEWORKS = UIKit SwiftUI Charts WidgetKit AudioToolbox
MyLittleEnergy_CODESIGN_FLAGS = -Sentitlements.plist


ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
MyLittleEnergy_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/application.mk
