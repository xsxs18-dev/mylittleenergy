include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = MyLittleEnergyModule

MyLittleEnergyModule_FILES = VXModule.x ../Shared/VXShared.m
MyLittleEnergyModule_CFLAGS = -fobjc-arc -I../Shared -Wno-deprecated-declarations -Wno-unknown-warning-option -Wno-unused-but-set-global
# Only the ObjC runtime is needed for %subclass, no hooking library.
MyLittleEnergyModule_LOGOSFLAGS = -c generator=internal
MyLittleEnergyModule_FRAMEWORKS = UIKit Foundation
MyLittleEnergyModule_INSTALL_PATH = /Library/ControlCenter/Bundles


ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
MyLittleEnergyModule_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/bundle.mk
