# Build `libgifsicle.so` For Android (arm64-v8a, x86_64)

This guide is for the current project at:
`/Users/lap60638-local/Desktop/Android/Projects/gifsicle`

Reference article used:
`https://www.likehide.com/blogs/android/bulding_and_using_gifsicle_in_android/`

The linked article builds an executable. This guide adapts the flow to build a JNI-callable shared library (`libgifsicle.so`) for:
- `arm64-v8a`
- `x86_64`

NDK locked in this guide:
- `ndk;28.2.13676358`

## 1. Verify NDK r28.2 is installed

Run:

```bash
ls -la /Users/lap60638-local/Library/Android/sdk/ndk/28.2.13676358
cat /Users/lap60638-local/Library/Android/sdk/ndk/28.2.13676358/source.properties | grep Pkg.Revision
```

Expected output includes:
- `Pkg.Revision = 28.2.13676358`

If missing, install with `sdkmanager` (Java 8 recommended for legacy `tools/bin/sdkmanager`):

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
export PATH="$JAVA_HOME/bin:$PATH"
yes | /Users/lap60638-local/Library/Android/sdk/tools/bin/sdkmanager --install "ndk;28.2.13676358"
```

## 2. Prepare project config files

From project root:

```bash
cd /Users/lap60638-local/Desktop/Android/Projects/gifsicle
```

Generate/refresh `config.h` (do not run `make install`):

```bash
autoreconf -i
./configure --disable-gifview --disable-gifdiff
```

## 3. Set `Application.mk` (2 ABIs only)

Create or replace `Application.mk`:

```makefile
APP_ABI := arm64-v8a x86_64
APP_PLATFORM := android-21
APP_STL := c++_shared
```

Notes:
- `APP_ABI` is intentionally limited to exactly 2 ABIs.
- `android-21` is a safe 64-bit minimum for these ABIs.

## 4. Create JNI bridge source

Create file `src/gifsicle_jni.c`:

```c
#include <jni.h>
#include <stdlib.h>
#include <string.h>

// We rename gifsicle's main() to gifsicle_main in Android.mk.
int gifsicle_main(int argc, char **argv);

JNIEXPORT jint JNICALL
Java_com_example_gifsicle_GifsicleBridge_run(
    JNIEnv *env,
    jobject thiz,
    jobjectArray args
) {
    (void)thiz;

    jsize count = (*env)->GetArrayLength(env, args);
    int argc = (int)count + 1;

    char **argv = (char **)calloc((size_t)argc + 1, sizeof(char *));
    if (argv == NULL) return -1;

    argv[0] = strdup("gifsicle");
    if (argv[0] == NULL) {
        free(argv);
        return -1;
    }

    for (jsize i = 0; i < count; ++i) {
        jstring jarg = (jstring)(*env)->GetObjectArrayElement(env, args, i);
        const char *utf = (*env)->GetStringUTFChars(env, jarg, NULL);
        if (utf == NULL) {
            for (int k = 0; k <= i; ++k) free(argv[k]);
            free(argv);
            return -1;
        }
        argv[i + 1] = strdup(utf);
        (*env)->ReleaseStringUTFChars(env, jarg, utf);
        (*env)->DeleteLocalRef(env, jarg);
        if (argv[i + 1] == NULL) {
            for (int k = 0; k <= i; ++k) free(argv[k]);
            free(argv);
            return -1;
        }
    }

    int rc = gifsicle_main(argc, argv);

    for (int i = 0; i < argc; ++i) free(argv[i]);
    free(argv);
    return (jint)rc;
}
```

Important:
- The JNI class path in this C function is `com/example/gifsicle/GifsicleBridge`.
- If your Kotlin package/class differs, update the function name accordingly.

## 5. Replace `Android.mk` to build shared library

Create or replace `Android.mk`:

```makefile
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
    src/xform.c \
    src/gifsicle_jni.c

LOCAL_CFLAGS := -DHAVE_CONFIG_H -Dmain=gifsicle_main

include $(BUILD_SHARED_LIBRARY)
```

Why `-Dmain=gifsicle_main`:
- `gifsicle.c` exports a `main()` function.
- Shared-library JNI entry should call it as a normal function.
- This define renames it at compile time to avoid symbol conflicts.

## 6. Build with NDK r28.2

From project root:

```bash
cd /Users/lap60638-local/Desktop/Android/Projects/gifsicle
/Users/lap60638-local/Library/Android/sdk/ndk/28.2.13676358/ndk-build \
  NDK_PROJECT_PATH=. \
  APP_BUILD_SCRIPT=Android.mk \
  NDK_APPLICATION_MK=Application.mk
```

Expected outputs:
- `libs/arm64-v8a/libgifsicle.so`
- `libs/x86_64/libgifsicle.so`

## 7. Copy `.so` files into Android app

In your Android app project, copy:
- `libs/arm64-v8a/libgifsicle.so` -> `app/src/main/jniLibs/arm64-v8a/libgifsicle.so`
- `libs/x86_64/libgifsicle.so` -> `app/src/main/jniLibs/x86_64/libgifsicle.so`

Directory should look like:

```text
app/src/main/jniLibs/
  arm64-v8a/libgifsicle.so
  x86_64/libgifsicle.so
```

## 8. Kotlin JNI usage example

Create `GifsicleBridge.kt`:

```kotlin
package com.example.gifsicle

object GifsicleBridge {
    init {
        System.loadLibrary("gifsicle")
    }

    external fun run(args: Array<String>): Int
}
```

Example call:

```kotlin
val rc = GifsicleBridge.run(
    arrayOf(
        "--optimize=3",
        "--lossy=40",
        "--output", outputGifPath,
        inputGifPath
    )
)
if (rc != 0) {
    // handle failure
}
```

## 9. Quick validation checklist

1. Both ABI files exist:
```bash
ls -la libs/arm64-v8a/libgifsicle.so libs/x86_64/libgifsicle.so
```
2. JNI symbol exists in each `.so`:
```bash
nm -gU libs/arm64-v8a/libgifsicle.so | grep Java_com_example_gifsicle_GifsicleBridge_run
nm -gU libs/x86_64/libgifsicle.so | grep Java_com_example_gifsicle_GifsicleBridge_run
```
3. App builds and loads library without `UnsatisfiedLinkError`.

## 10. Common beginner issues

1. `UnsatisfiedLinkError`: package/class mismatch between Kotlin and JNI function name.
2. `ndk-build: command not found`: use full path to NDK `ndk-build` shown above.
3. Missing ABI at runtime: verify only `arm64-v8a` and `x86_64` folders are present in `jniLibs`.
4. Build errors around `config.h`: rerun `autoreconf -i` and `./configure` in this repo root.
