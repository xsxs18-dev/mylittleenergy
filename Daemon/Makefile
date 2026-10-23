# A standalone daemon runs fine as arm64 on arm64e devices, so it never needs signed ObjC metadata.
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = mylittleenergyd

mylittleenergyd_FILES = main.m VXEngine.m VXHistory.m ../Shared/VXShared.m ../Shared/VXBattery.m
mylittleenergyd_CFLAGS = -fobjc-arc -I../Shared -DVX_VERSION=\"$(VX_VERSION)\" -Wno-deprecated-declarations
mylittleenergyd_FRAMEWORKS = Foundation
mylittleenergyd_CODESIGN_FLAGS = -Sentitlements.plist
mylittleenergyd_INSTALL_PATH = /usr/libexec


ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
mylittleenergyd_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/tool.mk
