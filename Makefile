ARCHS = arm64
TARGET = iphone:clang:latest:latest

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YouSubscribe
YouSubscribe_FILES = Tweak.x
YouSubscribe_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
