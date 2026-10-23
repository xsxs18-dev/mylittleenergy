# Rootless only (Dopamine, palera1n, nathanlr): make package
export TARGET = iphone:clang:latest:16.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME ?= rootless
export VX_VERSION := $(shell sed -n 's/^Version: //p' control)
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

SUBPROJECTS = Daemon Tweak CCModule App Widgets
include $(THEOS_MAKE_PATH)/aggregate.mk

before-package::
	$(ECHO_NOTHING)echo "Icon: file://$(THEOS_PACKAGE_INSTALL_PREFIX)/Applications/MyLittleEnergy.app/AppIcon60x60@3x.png" >> "$(THEOS_STAGING_DIR)/DEBIAN/control"$(ECHO_END)
