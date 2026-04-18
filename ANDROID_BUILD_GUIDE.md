# Building libgifsicle.so for Android

This guide covers building gifsicle as a native executable packaged as
`libgifsicle.so` for the **arm64-v8a** and **x86_64** Android ABIs.
The output binary supports **16 KB page size** devices (Android 15+, required
on Google Play from November 2025).

## Approach

The executable-as-so approach is used:

- gifsicle is compiled as a native **executable** (not a shared library).
- The binary is renamed to `libgifsicle.so` so Android's APK packager
  includes it under `lib/<ABI>/`.
- At runtime the app extracts the binary to its native library directory
  and invokes it via `Runtime.getRuntime().exec()`.

This avoids JNI glue code and lets you call gifsicle exactly like the
command-line tool.

---

## Prerequisites

| Requirement | Minimum version | Notes |
|---|---|---|
| Android NDK | **r28** | 16 KB ELF alignment is automatic |
| ndk-build | ships with NDK | located at `$NDK_ROOT/ndk-build` |
| macOS / Linux host | — | Windows hosts: use WSL2 |

### Verify your NDK version

```bash
$NDK_ROOT/ndk-build --version
# Expected: Android NDK version r28 or higher
```

If `NDK_ROOT` is not set, find the NDK path in Android Studio:
**SDK Manager → SDK Tools → NDK (Side by side)**.

---

## Repository layout

```
gifsicle/
├── Android.mk          # ndk-build module definition (executable)
├── Application.mk      # ABI / platform / STL settings
├── config.h            # Pre-generated configuration header (macOS-compatible)
├── include/            # lcdfgif and lcdf headers
└── src/                # gifsicle C source files
```

---

## Build steps

### 1. Clone and enter the repository

```bash
git clone https://github.com/kohler/gifsicle.git
cd gifsicle
```

If you are using this repository directly, skip the clone step.

### 2. Run ndk-build

Run from the **repository root** (the directory containing `Android.mk`):

```bash
$NDK_ROOT/ndk-build NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=Android.mk NDK_APPLICATION_MK=Application.mk
```

> `NDK_APPLICATION_MK` must be specified explicitly because ndk-build
> defaults to looking for `Application.mk` inside a `jni/` subdirectory.
> Without it, ndk-build ignores the root-level `Application.mk` and builds
> all default ABIs (including 32-bit armeabi-v7a), which will fail due to
> the config.h `SIZEOF_UNSIGNED_LONG 8` mismatch on 32-bit targets.

`ndk-build` reads `Android.mk` and `Application.mk` from the current
directory automatically.

A successful build prints output similar to:

```
[arm64-v8a] Compile  : gifsicle <= src/gifsicle.c
...
[arm64-v8a] Executable: gifsicle
[x86_64]    Compile  : gifsicle <= src/gifsicle.c
...
[x86_64]    Executable: gifsicle
```

### 3. Locate the output binaries

ndk-build places executables under `libs/`:

```
libs/
├── arm64-v8a/
│   └── gifsicle          ← arm64 executable
└── x86_64/
    └── gifsicle          ← x86_64 executable
```

### 4. Rename to libgifsicle.so

Android's APK packager only includes files matching the `lib*.so` pattern
under `lib/<ABI>/`. Rename the executables accordingly:

```bash
cp libs/arm64-v8a/gifsicle  libs/arm64-v8a/libgifsicle.so
cp libs/x86_64/gifsicle     libs/x86_64/libgifsicle.so
```

The files remain native executables internally — the `.so` extension is
only required for APK packaging.

---

## Verify 16 KB page size alignment

NDK r28+ automatically applies 16 KB ELF segment alignment. Confirm with
`llvm-objdump` (bundled in the NDK):

```bash
# arm64-v8a
$NDK_ROOT/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-objdump \
    -p libs/arm64-v8a/libgifsicle.so | grep LOAD

# x86_64
$NDK_ROOT/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-objdump \
    -p libs/x86_64/libgifsicle.so | grep LOAD
```

Look for `align 2**14` in the output (2^14 = 16384 = 16 KB):

```
LOAD off    0x0000000000000000 vaddr 0x0000000000000000 ... align 2**14
LOAD off    0x0000000000010000 vaddr 0x0000000000010000 ... align 2**14
```

A value of `2**13` or lower means alignment is missing — this should not
happen with NDK r28+.

> **Linux hosts:** replace `darwin-x86_64` with `linux-x86_64` in the
> toolchain path above.

---

## Integrate into your Android project

### Copy to jniLibs

Copy the renamed binaries into your Android module's `jniLibs` directory:

```
app/src/main/jniLibs/
├── arm64-v8a/
│   └── libgifsicle.so
└── x86_64/
    └── libgifsicle.so
```

### Automate with Gradle (optional)

Add a copy task to your module's `build.gradle` so the rename happens
automatically after each ndk-build run:

```groovy
// build.gradle (app module)
tasks.register('copyGifsicleLibs', Copy) {
    def ndkBuildOut = rootProject.file('../gifsicle/libs')
    ['arm64-v8a', 'x86_64'].each { abi ->
        from("$ndkBuildOut/$abi/gifsicle") {
            rename 'gifsicle', 'libgifsicle.so'
            into abi
        }
    }
    into 'src/main/jniLibs'
}
preBuild.dependsOn copyGifsicleLibs
```

### Extract and execute at runtime (Kotlin)

```kotlin
import java.io.File

fun getGifsiclePath(context: android.content.Context): String {
    // On API 21+, the system extracts lib*.so files to nativeLibraryDir
    return File(context.applicationInfo.nativeLibraryDir, "libgifsicle.so")
        .absolutePath
}

fun runGifsicle(context: android.content.Context, vararg args: String): Int {
    val binary = getGifsiclePath(context)
    // Ensure the binary is executable (system sets this on extraction)
    File(binary).setExecutable(true)

    val command = arrayOf(binary) + args
    val process = Runtime.getRuntime().exec(command)
    return process.waitFor()
}

// Example: optimize a GIF to 256 colors at compression level 3
// runGifsicle(context, "--optimize=3", "--colors=256", "-o", outputPath, inputPath)
```

---

## What changed from the original build files

### Android.mk

| Field | Before | After | Reason |
|---|---|---|---|
| `BUILD_SHARED_LIBRARY` | shared library | `BUILD_EXECUTABLE` | executable approach |
| `LOCAL_SRC_FILES` | included `gifsicle_jni.c` | removed | JNI not needed |
| `LOCAL_CFLAGS` | `-Dmain=gifsicle_main` | removed | real `main()` is used |
| `LOCAL_LDLIBS` | not set | `-lm` | `pow()` and `cbrtf()` require libm |

### Application.mk

| Field | Before | After | Reason |
|---|---|---|---|
| `APP_STL` | `c++_shared` | `none` | pure C — no C++ runtime needed |

### config.h

The existing `config.h` (generated on macOS) is used as-is. It is
compatible with 64-bit Android targets (arm64-v8a, x86_64) because:

- Both macOS and Android NDK use Clang as the compiler.
- Both platforms use the LP64 data model on 64-bit hardware
  (`sizeof(unsigned long) == 8`, `sizeof(void*) == 8`).
- SIMD defines (`HAVE_SIMD`, `HAVE_VECTOR_SIZE_VECTOR_TYPES`,
  `HAVE_EXT_VECTOR_TYPE_VECTOR_TYPES`) use portable Clang compiler
  extensions, not CPU intrinsics.
- All referenced libc functions (`mkstemp`, `cbrtf`, `random`, pthreads)
  are available in Android bionic from API 19+.

---

## Troubleshooting

### `undefined reference to 'pow'` or `'cbrtf'`
`LOCAL_LDLIBS := -lm` is already set in `Android.mk`. If you see this
error, confirm you are running ndk-build from the repository root where
`Android.mk` lives.

### `align 2**13` in llvm-objdump output
Your NDK version is older than r28. Upgrade to NDK r28+ for automatic
16 KB alignment, or add the following to `Android.mk` as a workaround:

```makefile
LOCAL_LDFLAGS += -Wl,-z,max-page-size=16384
```

### `ndk-build: command not found`
Set `NDK_ROOT` to your NDK installation path and use the full path:

```bash
export NDK_ROOT=~/Library/Android/sdk/ndk/<version>
$NDK_ROOT/ndk-build ...
```

### Binary not executable on device
After copying `libgifsicle.so` into `jniLibs`, the system automatically
sets the executable bit when extracting to `nativeLibraryDir`. If calling
the binary fails with "Permission denied", call `File.setExecutable(true)`
before the first `exec()` call (shown in the Kotlin snippet above).
