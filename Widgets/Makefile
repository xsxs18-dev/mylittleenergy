ARCHS = arm64

include $(THEOS)/makefiles/common.mk

# Built as a plain executable so the Swift @main of the widget bundle is the entry point.
TOOL_NAME = MyLittleEnergyWidgets

MyLittleEnergyWidgets_FILES = $(wildcard Sources/*.swift) ../Shared/VXShared.m
MyLittleEnergyWidgets_CFLAGS = -fobjc-arc -I../Shared -Wno-deprecated-declarations
MyLittleEnergyWidgets_SWIFT_BRIDGING_HEADER = MyLittleEnergyWidgets-Bridging-Header.h
MyLittleEnergyWidgets_SWIFTFLAGS = -application-extension
MyLittleEnergyWidgets_LDFLAGS = -fapplication-extension
MyLittleEnergyWidgets_FRAMEWORKS = SwiftUI WidgetKit Charts
MyLittleEnergyWidgets_CODESIGN_FLAGS = -Sentitlements.plist
MyLittleEnergyWidgets_INSTALL_PATH = /Applications/MyLittleEnergy.app/PlugIns/MyLittleEnergyWidgets.appex


ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
MyLittleEnergyWidgets_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/tool.mk

internal-stage::
	$(ECHO_NOTHING)cp Info.plist "$(THEOS_STAGING_DIR)/Applications/MyLittleEnergy.app/PlugIns/MyLittleEnergyWidgets.appex/Info.plist"$(ECHO_END)
	$(ECHO_NOTHING)cp -R Resources/*.lproj "$(THEOS_STAGING_DIR)/Applications/MyLittleEnergy.app/PlugIns/MyLittleEnergyWidgets.appex/"$(ECHO_END)
