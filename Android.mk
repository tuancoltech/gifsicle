LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE := gifsicle
LOCAL_C_INCLUDES := $(LOCAL_PATH)/include
LOCAL_SRC_FILES := \
    src/clp.c \
    src/fmalloc.c \
    src/giffunc.c \
    src/gifread.c \
    src/gifsicle.c \
    src/gifunopt.c \
    src/gifwrite.c \
    src/kcolor.c \
    src/merge.c \
    src/optimize.c \
    src/quantize.c \
    src/support.c \
    src/xform.c

LOCAL_CFLAGS  := -DHAVE_CONFIG_H
LOCAL_LDLIBS  := -lm

include $(BUILD_EXECUTABLE)
