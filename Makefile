# =============================================================================
#  YTLiteSkipSilence - Theos Makefile
#  Adds Overcast-style "Skip Silence" + Voice Boost to YouTube via YTLite
# =============================================================================

# ---- package scheme (rootless / roothide) -----------------------------------
ifeq ($(ROOTLESS),1)
THEOS_PACKAGE_SCHEME = rootless
else ifeq ($(ROOTHIDE),1)
THEOS_PACKAGE_SCHEME = roothide
endif

# ---- build flags ------------------------------------------------------------
DEBUG             = 0
FINALPACKAGE      = 1
ARCHS             = arm64 arm64e
PACKAGE_VERSION   = 1.0.0

TARGET := iphone:clang:16.5:13.0

# ---- theos bootstrap --------------------------------------------------------
include $(THEOS)/makefiles/common.mk

# ---- tweak definition -------------------------------------------------------
TWEAK_NAME = YTLiteSkipSilence

$(TWEAK_NAME)_FRAMEWORKS  = UIKit Foundation AVFoundation CoreMedia AudioToolbox CoreAudio
$(TWEAK_NAME)_WEAKFRAMEWORKS = MediaToolbox
$(TWEAK_NAME)_CFLAGS   = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
$(TWEAK_NAME)_LDFLAGS  = -framework AudioToolbox -framework CoreAudio -framework AVFoundation

# Wildcard picks up every .x in repo root; Utils .m files listed explicitly.
$(TWEAK_NAME)_FILES = \
	$(wildcard *.x) \
	Utils/SkipSilenceManager.m \
	Utils/SkipSilenceDefaults.m \
	Utils/NSBundle+YTSkipSilence.m \
	Utils/Reachability.m

# Vendor headers (PoomSmart/YouTubeHeader + PSHeader + YTVideoOverlay) must
# be resolvable either via THEOS_INCLUDE_PATH or as sibling checkouts - see README.md.
$(TWEAK_NAME)_CFLAGS += -I$(THEOS)/include -I../YouTubeHeader -I../PSHeader -I../YTVideoOverlay

# Bundle resources - installed into the package's /Library/Application Support/
$(TWEAK_NAME)_BUNDLE_RESOURCES = Resources/YTLiteSkipSilence.bundle

include $(THEOS_MAKE_PATH)/tweak.mk

# Stage the resources bundle into /Library/Application Support/ inside the .deb
before-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/Application Support"
	@cp -R Resources/YTLiteSkipSilence.bundle "$(THEOS_STAGING_DIR)/Library/Application Support/" 2>/dev/null || true
	@echo "=> Staged YTLiteSkipSilence.bundle into /Library/Application Support/"
