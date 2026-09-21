#!/bin/bash -e
#
# Builds universal (x86_64 + arm64) versions of the Syphon framework binary
# and the JSyphon JNI library, without requiring Xcode (Command Line Tools
# plus a JDK for the JNI headers is enough).
#
# JavaNativeFoundation is no longer shipped with the macOS SDK, so the
# sources vendored under native_src/jnf (from apple/openjdk,
# xcodejdk14-release branch, APSL 2.0) are compiled statically into
# libJSyphon.jnilib.
#
# Requires: macOS Command Line Tools, a JDK (JAVA_HOME or Homebrew openjdk).
#
# Usage: ./build_universal.sh [output-dir]   (default: ../native_libs)

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSYPHON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
JAVA_DIR="$(cd "$JSYPHON_DIR/.." && pwd)"
SYPHON_FW_DIR="$JAVA_DIR/Syphon-Framework"
SHARED_DIR="$JAVA_DIR/Shared"
JNF_DIR="$SCRIPT_DIR/jnf"
BUILD_DIR="$SCRIPT_DIR/build_universal"
OUT_DIR="$(cd "${1:-$JSYPHON_DIR/native_libs}" && pwd)"

if [ ! -f "${JAVA_HOME:-}/include/jni.h" ]; then
    if [ -d /opt/homebrew/opt/openjdk@17/include ]; then
        JAVA_HOME=/opt/homebrew/opt/openjdk@17
    else
        JAVA_HOME="$(dirname "$(dirname "$(command -v javac)")")"
    fi
fi
if [ ! -f "$JAVA_HOME/include/jni.h" ]; then
    echo "error: jni.h not found under JAVA_HOME=$JAVA_HOME (set JAVA_HOME to a full JDK)" >&2
    exit 1
fi

ARCHS="x86_64 arm64"
DEPLOY_TARGET_x86_64=10.13
DEPLOY_TARGET_arm64=11.0

OBJCFLAGS="-fblocks -Wno-deprecated-declarations -Wno-unused-function -g0 -Os"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/include/JavaNativeFoundation" "$BUILD_DIR/include/Syphon"

cp "$JNF_DIR"/*.h "$BUILD_DIR/include/JavaNativeFoundation/"
cp "$SYPHON_FW_DIR"/*.h "$BUILD_DIR/include/Syphon/"

grep -v '^[[:space:]]*//' "$SYPHON_FW_DIR/Exported_Symbols.exp" | grep -v '^[[:space:]]*$' > "$BUILD_DIR/Exported_Symbols.exp"

INCLUDES=(-I "$BUILD_DIR/include" -I "$SYPHON_FW_DIR" -I "$SHARED_DIR" -I "$SCRIPT_DIR" -I "$JAVA_HOME/include" -I "$JAVA_HOME/include/darwin")

SYPHON_SOURCES=("$SYPHON_FW_DIR"/*.m "$SYPHON_FW_DIR"/*.c)
JSYPHON_SOURCES=("$SCRIPT_DIR"/jsyphon_JSyphon*.m "$JNF_DIR"/*.m "$SHARED_DIR/SyphonNameboundClient.m")

for ARCH in $ARCHS; do
    case "$ARCH" in
        x86_64) MIN=$DEPLOY_TARGET_x86_64 ;;
        arm64)  MIN=$DEPLOY_TARGET_arm64 ;;
    esac
    COMMON=(-arch "$ARCH" -mmacosx-version-min="$MIN" -fPIC $OBJCFLAGS "${INCLUDES[@]}")

    echo "==> Building Syphon ($ARCH)"
    clang -dynamiclib -o "$BUILD_DIR/Syphon-$ARCH" \
        "${COMMON[@]}" -fobjc-arc \
        -DSYPHON_CORE_RESTORE \
        -include "$SYPHON_FW_DIR/Syphon_Prefix.pch" \
        "${SYPHON_SOURCES[@]}" \
        -install_name "@loader_path/Syphon" \
        -current_version 1.0.0 -compatibility_version 1.0.0 \
        -Wl,-exported_symbols_list,"$BUILD_DIR/Exported_Symbols.exp" \
        -framework Cocoa -framework IOSurface -framework OpenGL -framework CoreVideo -framework Metal

    echo "==> Building libJSyphon.jnilib ($ARCH)"
    clang -dynamiclib -o "$BUILD_DIR/libJSyphon.jnilib-$ARCH" \
        "${COMMON[@]}" -fno-objc-arc \
        "${JSYPHON_SOURCES[@]}" \
        -install_name "@rpath/libJSyphon.jnilib" \
        -current_version 1.0.0 -compatibility_version 1.0.0 \
        "$BUILD_DIR/Syphon-$ARCH" \
        -Wl,-undefined,dynamic_lookup \
        -framework Cocoa -framework OpenGL -framework CoreData
done

echo "==> Creating universal binaries"
lipo -create -output "$BUILD_DIR/Syphon" "$BUILD_DIR/Syphon-x86_64" "$BUILD_DIR/Syphon-arm64"
lipo -create -output "$BUILD_DIR/libJSyphon.jnilib" "$BUILD_DIR/libJSyphon.jnilib-x86_64" "$BUILD_DIR/libJSyphon.jnilib-arm64"

echo "==> Ad-hoc code signing"
codesign --force --sign - "$BUILD_DIR/Syphon"
codesign --force --sign - "$BUILD_DIR/libJSyphon.jnilib"

echo "==> Installing to $OUT_DIR"
cp "$BUILD_DIR/Syphon" "$OUT_DIR/Syphon"
cp "$BUILD_DIR/libJSyphon.jnilib" "$OUT_DIR/libJSyphon.jnilib"

lipo -info "$OUT_DIR/Syphon" "$OUT_DIR/libJSyphon.jnilib"
echo "Done."
