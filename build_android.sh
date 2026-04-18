#!/usr/bin/env bash
# =============================================================================
# build_android.sh
# Builds libgifsicle.so for Android (arm64-v8a, x86_64)
#
# REQUIREMENTS — read before running
# ------------------------------------
#  1. Host OS    : macOS or Linux. Windows users must run inside WSL2.
#
#  2. Android NDK r28 or higher must be installed.
#     Install via Android Studio:
#       SDK Manager → SDK Tools → NDK (Side by side) → choose 28.x or later
#     Or via sdkmanager CLI:
#       sdkmanager "ndk;28.2.13676358"
#
#  3. NDK location (choose one):
#     a) Set the NDK_ROOT environment variable before running:
#          export NDK_ROOT=~/Library/Android/sdk/ndk/28.2.13676358
#        then run the script.
#     b) Leave NDK_ROOT unset — the script will auto-detect the highest r28+
#        NDK version found under:
#          ~/Library/Android/sdk/ndk/          (macOS default)
#          ~/Android/Sdk/ndk/                  (Linux default)
#          $ANDROID_SDK_ROOT/ndk/              (if ANDROID_SDK_ROOT is set)
#          $ANDROID_HOME/ndk/                  (if ANDROID_HOME is set)
#
#  4. Run this script from the gifsicle repository root (where Android.mk is):
#          bash build_android.sh
#
#  5. No other tools are required. ndk-build and llvm-objdump are bundled
#     with the NDK.
#
# USAGE
# -----
#   bash build_android.sh            # incremental build
#   bash build_android.sh --clean    # clean then full rebuild
#
# OUTPUT
#   libs/arm64-v8a/libgifsicle.so
#   libs/x86_64/libgifsicle.so
# =============================================================================

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIN_NDK_MAJOR=28
ABIS=(arm64-v8a x86_64)

# ── Terminal colours (suppressed when not a tty) ──────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi

info()    { echo -e "${BOLD}$*${NC}"; }
success() { echo -e "${GREEN}✔  $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠  $*${NC}"; }
die()     { echo -e "${RED}✖  $*${NC}" >&2; exit 1; }

# ── Argument parsing ──────────────────────────────────────────────────────────
CLEAN=false
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=true ;;
        --help|-h)
            sed -n '/^# USAGE/,/^# OUTPUT/{/^#/!d; s/^# \{0,2\}//; p}' "$0"
            exit 0
            ;;
        *) die "Unknown argument: $arg. Use --clean or --help." ;;
    esac
done

# ── NDK discovery ─────────────────────────────────────────────────────────────
find_ndk() {
    # Honour explicit override first
    if [[ -n "${NDK_ROOT:-}" ]]; then
        echo "$NDK_ROOT"
        return
    fi

    local -a search_dirs=(
        "$HOME/Library/Android/sdk/ndk"
        "$HOME/Android/Sdk/ndk"
    )
    [[ -n "${ANDROID_SDK_ROOT:-}" ]] && search_dirs+=("${ANDROID_SDK_ROOT}/ndk")
    [[ -n "${ANDROID_HOME:-}"     ]] && search_dirs+=("${ANDROID_HOME}/ndk")

    local best_ver="" best_path=""
    for base in "${search_dirs[@]}"; do
        [[ -d "$base" ]] || continue
        for candidate in "$base"/*/; do
            [[ -d "$candidate" ]] || continue
            local ver major
            ver="$(basename "$candidate")"
            major="$(echo "$ver" | cut -d. -f1)"
            # Accept only numeric major versions >= MIN_NDK_MAJOR
            [[ "$major" =~ ^[0-9]+$ ]] || continue
            (( major >= MIN_NDK_MAJOR ))  || continue
            # Keep the lexicographically highest version string
            [[ -z "$best_ver" || "$ver" > "$best_ver" ]] && { best_ver="$ver"; best_path="${candidate%/}"; }
        done
    done

    echo "$best_path"
}

# ── NDK version (reads source.properties bundled with every NDK) ──────────────
get_ndk_revision() {
    local ndk_root="$1"
    local props="$ndk_root/source.properties"
    if [[ -f "$props" ]]; then
        grep "Pkg.Revision" "$props" | cut -d= -f2 | tr -d ' '
    else
        basename "$ndk_root"
    fi
}

get_ndk_major() {
    get_ndk_revision "$1" | cut -d. -f1
}

# ── Alignment check ───────────────────────────────────────────────────────────
check_alignment() {
    local objdump="$1" so="$2" abi="$3"

    [[ -f "$objdump" ]] || { warn "$abi: llvm-objdump not found, skipping alignment check."; return; }

    # Extract the minimum exponent from all LOAD segment align fields.
    # Format: "align 2**14" → 14
    # Uses grep+sed instead of gawk to stay compatible with macOS BSD awk.
    local min_exp
    min_exp=$(
        "$objdump" -p "$so" 2>/dev/null \
            | grep "LOAD" \
            | grep -oE "align 2\*\*[0-9]+" \
            | sed 's/align 2\*\*//' \
            | sort -n \
            | head -1
    )

    if [[ -z "$min_exp" ]]; then
        warn "$abi: could not parse LOAD segment alignment."
    elif (( min_exp >= 14 )); then
        success "$abi: 16 KB alignment confirmed  (align 2**$min_exp)"
    else
        warn "$abi: alignment is only 2**$min_exp (expected 2**14 or higher)."
        warn "      Upgrade to NDK r28+ or add to Android.mk: LOCAL_LDFLAGS += -Wl,-z,max-page-size=16384"
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    info "=== gifsicle Android build ==="
    echo

    # ── Locate NDK ────────────────────────────────────────────────────────────
    info "Locating NDK..."
    local ndk_root
    ndk_root="$(find_ndk)"
    [[ -n "$ndk_root" ]] || die "NDK r${MIN_NDK_MAJOR}+ not found.\nSet NDK_ROOT to your NDK installation path and re-run."

    local major revision
    revision="$(get_ndk_revision "$ndk_root")"
    major="$(echo "$revision" | cut -d. -f1)"

    (( major >= MIN_NDK_MAJOR )) \
        || die "NDK r$major found at $ndk_root\nNDK r${MIN_NDK_MAJOR}+ is required."

    success "NDK r${revision}  →  $ndk_root"
    echo

    # ── Verify required build files ───────────────────────────────────────────
    for f in Android.mk Application.mk config.h; do
        [[ -f "$SCRIPT_DIR/$f" ]] || die "Required file not found: $SCRIPT_DIR/$f"
    done

    # ── Optional clean ────────────────────────────────────────────────────────
    if [[ "$CLEAN" == true ]]; then
        info "Cleaning previous build artifacts..."
        rm -rf "$SCRIPT_DIR/obj" "$SCRIPT_DIR/libs"
        success "Cleaned obj/ and libs/"
        echo
    fi

    # ── ndk-build ─────────────────────────────────────────────────────────────
    info "Running ndk-build  (ABIs: ${ABIS[*]})..."
    echo
    "$ndk_root/ndk-build" \
        NDK_PROJECT_PATH="$SCRIPT_DIR" \
        APP_BUILD_SCRIPT="$SCRIPT_DIR/Android.mk" \
        NDK_APPLICATION_MK="$SCRIPT_DIR/Application.mk"
    echo

    # ── Rename executables to libgifsicle.so ──────────────────────────────────
    info "Renaming executables to libgifsicle.so..."
    for abi in "${ABIS[@]}"; do
        local src="$SCRIPT_DIR/libs/$abi/gifsicle"
        local dst="$SCRIPT_DIR/libs/$abi/libgifsicle.so"
        [[ -f "$src" ]] || die "Expected output missing: $src\nThe ndk-build step may have failed."
        cp "$src" "$dst"
        success "$abi  →  $dst"
    done
    echo

    # ── 16 KB alignment verification ─────────────────────────────────────────
    info "Verifying 16 KB page-size alignment..."
    local host_tag
    case "$(uname -s)" in
        Darwin) host_tag="darwin-x86_64" ;;
        Linux)  host_tag="linux-x86_64"  ;;
        *)      host_tag="" ;;
    esac

    if [[ -n "$host_tag" ]]; then
        local objdump="$ndk_root/toolchains/llvm/prebuilt/$host_tag/bin/llvm-objdump"
        for abi in "${ABIS[@]}"; do
            check_alignment "$objdump" "$SCRIPT_DIR/libs/$abi/libgifsicle.so" "$abi"
        done
    else
        warn "Unrecognised host OS — skipping alignment check."
    fi
    echo

    # ── Summary ───────────────────────────────────────────────────────────────
    info "=== Build complete ==="
    for abi in "${ABIS[@]}"; do
        echo "  $SCRIPT_DIR/libs/$abi/libgifsicle.so"
    done
}

main
