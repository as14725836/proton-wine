#!/bin/bash

set -eo pipefail

###############################################################################
# Wine / Proton ARM64EC
#
# Target:
#   Termux glibc
#   Termux:X11
#   Optional Wayland
#   ARM64EC / AArch64 / i386 PE
#
# Native Unix ABI:
#   AArch64 GNU/Linux glibc
#   aarch64-linux-gnu
#
# Windows PE:
#   arm64ec
#   aarch64
#   i386
#
###############################################################################

###############################################################################
# 0. Basic target
###############################################################################

export ARCH="${ARCH:-aarch64}"
export WIN_ARCH="${WIN_ARCH:-arm64ec,aarch64,i386}"

export OUTPUT_DIR="${OUTPUT_DIR:-$HOME/compiled-files-aarch64}"

###############################################################################
# 1. Termux glibc filesystem
###############################################################################

#
# Android runtime:
#
#   /data/data/com.termux/files/usr
#
# Termux glibc runtime:
#
#   /data/data/com.termux/files/usr/glibc
#
# CI staging:
#
#   $GLIBC_ROOTFS/data/data/com.termux/files/usr/glibc
#
# IMPORTANT:
#   GLIBC_PREFIX is the CI staging path.
#   RUNTIME_PATH is the actual Android runtime path.
#

export TERMUX_PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"

export GLIBC_ROOTFS="${GLIBC_ROOTFS:-$HOME/termuxfs/aarch64-glibc}"

export GLIBC_PREFIX="${GLIBC_PREFIX:-${GLIBC_ROOTFS}${TERMUX_PREFIX}/glibc}"

export GLIBC_LIB="$GLIBC_PREFIX/lib"
export GLIBC_INCLUDE="$GLIBC_PREFIX/include"
export GLIBC_SHARE="$GLIBC_PREFIX/share"
export GLIBC_ETC="$GLIBC_PREFIX/etc"

export deps="$GLIBC_PREFIX"

#
# Actual Android runtime path.
#
# NEVER use GLIBC_PREFIX for runtime RPATH.
#

export RUNTIME_PATH="${RUNTIME_PATH:-$TERMUX_PREFIX/glibc}"

#
# Wine installation inside staged glibc rootfs.
#

export install_dir="${install_dir:-$GLIBC_PREFIX/opt/wine}"

###############################################################################
# 2. CI temporary directory
###############################################################################

#
# GitHub Actions cannot write:
#
#   /data/data/com.termux/files/usr/tmp
#
# Therefore CI uses a staging-local temporary directory.
#

export TERMUX_TMPDIR="${TERMUX_TMPDIR:-$GLIBC_ROOTFS/tmp/runtime}"

mkdir -p \
    "$GLIBC_PREFIX" \
    "$GLIBC_LIB" \
    "$GLIBC_INCLUDE" \
    "$GLIBC_SHARE" \
    "$GLIBC_ETC" \
    "$GLIBC_PREFIX/opt" \
    "$TERMUX_TMPDIR"

export TMPDIR="$TERMUX_TMPDIR"
export TMP="$TERMUX_TMPDIR"
export TEMP="$TERMUX_TMPDIR"

###############################################################################
# 3. Display
###############################################################################

#
# Primary runtime backend:
#
#   Termux:X11
#
# Wayland remains optional.
#

export DISPLAY="${DISPLAY:-:0}"
export GDK_BACKEND="${GDK_BACKEND:-x11}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
export TERMUX_X11_FORCE_FLIP="${TERMUX_X11_FORCE_FLIP:-1}"

###############################################################################
# 4. Native Unix target
###############################################################################

export TARGET="${TARGET:-aarch64-linux-gnu}"

case "$TARGET" in
    *android*)
        echo
        echo "FATAL: Android/Bionic TARGET is forbidden:"
        echo "  $TARGET"
        exit 1
        ;;
esac

###############################################################################
# 5. Native glibc compiler
###############################################################################

if [ "$(uname -m)" = "aarch64" ]; then

    export GLIBC_CC="${GLIBC_CC:-gcc}"
    export GLIBC_CXX="${GLIBC_CXX:-g++}"
    export GLIBC_AS="${GLIBC_AS:-as}"
    export GLIBC_AR="${GLIBC_AR:-ar}"
    export GLIBC_LD="${GLIBC_LD:-ld}"
    export GLIBC_RANLIB="${GLIBC_RANLIB:-ranlib}"
    export GLIBC_STRIP="${GLIBC_STRIP:-strip}"

else

    export GLIBC_TOOLCHAIN="${GLIBC_TOOLCHAIN:-/opt/aarch64-linux-gnu}"

    export GLIBC_CC="${GLIBC_CC:-$GLIBC_TOOLCHAIN/bin/aarch64-linux-gnu-gcc}"
    export GLIBC_CXX="${GLIBC_CXX:-$GLIBC_TOOLCHAIN/bin/aarch64-linux-gnu-g++}"
    export GLIBC_AS="${GLIBC_AS:-$GLIBC_TOOLCHAIN/bin/aarch64-linux-gnu-as}"
    export GLIBC_AR="${GLIBC_AR:-$GLIBC_TOOLCHAIN/bin/aarch64-linux-gnu-ar}"
    export GLIBC_LD="${GLIBC_LD:-$GLIBC_TOOLCHAIN/bin/aarch64-linux-gnu-ld}"
    export GLIBC_RANLIB="${GLIBC_RANLIB:-$GLIBC_TOOLCHAIN/bin/aarch64-linux-gnu-ranlib}"
    export GLIBC_STRIP="${GLIBC_STRIP:-$GLIBC_TOOLCHAIN/bin/aarch64-linux-gnu-strip}"

fi

###############################################################################
# 6. LLVM-MinGW
###############################################################################

#
# LLVM-MinGW is used ONLY for Windows PE targets.
#
# The workflow must provide the host-appropriate path.
#

export LLVM_MINGW_TOOLCHAIN="${LLVM_MINGW_TOOLCHAIN:?LLVM_MINGW_TOOLCHAIN is required}"

if [ ! -d "$LLVM_MINGW_TOOLCHAIN" ]; then

    echo
    echo "FATAL: LLVM-MinGW directory not found:"
    echo "  $LLVM_MINGW_TOOLCHAIN"
    exit 1

fi

if [ ! -x "$LLVM_MINGW_TOOLCHAIN/clang" ]; then

    echo
    echo "FATAL: LLVM-MinGW clang not found:"
    echo "  $LLVM_MINGW_TOOLCHAIN/clang"
    exit 1

fi

if [ ! -x "$LLVM_MINGW_TOOLCHAIN/llvm-dlltool" ]; then

    echo
    echo "FATAL: LLVM-MinGW llvm-dlltool not found:"
    echo "  $LLVM_MINGW_TOOLCHAIN/llvm-dlltool"
    exit 1

fi

export PATH="$LLVM_MINGW_TOOLCHAIN:$PATH"

###############################################################################
# 7. ccache
###############################################################################

if command -v ccache >/dev/null 2>&1; then

    export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"

    ccache -M "${CCACHE_MAXSIZE:-5G}" >/dev/null 2>&1 || true

    #
    # IMPORTANT:
    #
    # Do NOT create:
    #
    #   $HOME/ccache-bin/gcc -> ccache
    #
    # while also using:
    #
    #   CC="ccache gcc"
    #
    # because gcc may resolve back to ccache recursively.
    #

    export CC="ccache $GLIBC_CC"
    export CXX="ccache $GLIBC_CXX"

else

    export CC="$GLIBC_CC"
    export CXX="$GLIBC_CXX"

fi

export AS="$GLIBC_AS"
export AR="$GLIBC_AR"
export LD="$GLIBC_LD"
export RANLIB="$GLIBC_RANLIB"
export STRIP="$GLIBC_STRIP"

export DLLTOOL="$LLVM_MINGW_TOOLCHAIN/llvm-dlltool"

###############################################################################
# 8. Compiler flags
###############################################################################

export C_OPTS="${C_OPTS:--g0 -O2 -Wno-declaration-after-statement -Wno-implicit-function-declaration -Wno-int-conversion}"

export CFLAGS="$C_OPTS"
export CXXFLAGS="$C_OPTS"

#
# PE-side ARM64EC / MinGW flags.
#

export CROSSCFLAGS="${CROSSCFLAGS:--g0 -O2}"

###############################################################################
# 9. glibc staging include / library
###############################################################################

#
# Do NOT use Android NDK.
#
# Do NOT use normal Termux/Bionic include/lib directories.
#

export CPPFLAGS="-I$GLIBC_INCLUDE"

#
# IMPORTANT:
#
# $GLIBC_PREFIX is a CI path.
#
# It MUST NOT appear in the final Android ELF RPATH.
#
# Use the actual runtime path instead.
#

export LDFLAGS="-L$GLIBC_LIB \
-Wl,-rpath,$RUNTIME_PATH/lib \
-Wl,-rpath,$RUNTIME_PATH/opt/wine/lib"

###############################################################################
# 10. pkg-config
###############################################################################

#
# The staged .pc files already describe the Termux glibc tree.
#
# Do not apply another SYSROOT prefix unless the package tree specifically
# requires it.
#

unset PKG_CONFIG_SYSROOT_DIR

export PKG_CONFIG_LIBDIR="$GLIBC_LIB/pkgconfig:$GLIBC_LIB/$TARGET/pkgconfig:$GLIBC_SHARE/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"

###############################################################################
# 11. aclocal
###############################################################################

export ACLOCAL_PATH="$GLIBC_LIB/aclocal:$GLIBC_SHARE/aclocal"

###############################################################################
# 12. FreeType
###############################################################################

export FREETYPE_CFLAGS="-I$GLIBC_INCLUDE/freetype2"

###############################################################################
# 13. PulseAudio
###############################################################################

export PULSE_CFLAGS="-I$GLIBC_INCLUDE/pulse"
export PULSE_LIBS="-L$GLIBC_LIB -lpulse"

###############################################################################
# 14. SDL2
###############################################################################

export SDL2_CFLAGS="-I$GLIBC_INCLUDE/SDL2"
export SDL2_LIBS="-L$GLIBC_LIB -lSDL2"

###############################################################################
# 15. Fontconfig
###############################################################################

export FONTCONFIG_LIBS="-L$GLIBC_LIB -lfontconfig -lfreetype -lexpat"

###############################################################################
# 16. X11
###############################################################################

#
# Primary display:
#
#   Wine
#     -> winex11.drv
#     -> libX11
#     -> Termux:X11 :0
#
# These libraries MUST be glibc-compatible.
#

export X_CFLAGS="-I$GLIBC_INCLUDE"

export X_LIBS="-L$GLIBC_LIB \
-lX11 \
-lXext \
-lXrender \
-lXrandr \
-lXfixes \
-lXdamage \
-lXcomposite \
-lXinerama \
-lXcursor \
-lXi \
-lXxf86vm \
-lxcb \
-lXau \
-lXdmcp"

###############################################################################
# 17. GStreamer
###############################################################################

export GSTREAMER_CFLAGS="-I$GLIBC_INCLUDE/gstreamer-1.0 \
-I$GLIBC_INCLUDE/glib-2.0 \
-I$GLIBC_LIB/glib-2.0/include \
-I$GLIBC_INCLUDE"

export GSTREAMER_LIBS="-L$GLIBC_LIB \
-lgstgl-1.0 \
-lgstapp-1.0 \
-lgstvideo-1.0 \
-lgstaudio-1.0 \
-lgsttag-1.0 \
-lgstbase-1.0 \
-lgstreamer-1.0 \
-lglib-2.0 \
-lgobject-2.0 \
-lgio-2.0"

###############################################################################
# 18. FFmpeg
###############################################################################

export FFMPEG_CFLAGS="-I$GLIBC_INCLUDE/libavutil \
-I$GLIBC_INCLUDE/libavcodec \
-I$GLIBC_INCLUDE/libavformat"

export FFMPEG_LIBS="-L$GLIBC_LIB \
-lavutil \
-lavcodec \
-lavformat"

###############################################################################
# 19. Wayland
###############################################################################

export WAYLAND_CLIENT_CFLAGS="-I$GLIBC_INCLUDE"
export WAYLAND_CLIENT_LIBS="-L$GLIBC_LIB -lwayland-client"

export WAYLAND_EGL_CFLAGS="-I$GLIBC_INCLUDE"
export WAYLAND_EGL_LIBS="-L$GLIBC_LIB -lwayland-egl"

export XKBCOMMON_CFLAGS="-I$GLIBC_INCLUDE"
export XKBCOMMON_LIBS="-L$GLIBC_LIB -lxkbcommon"

export XKBREGISTRY_CFLAGS="-I$GLIBC_INCLUDE"
export XKBREGISTRY_LIBS="-L$GLIBC_LIB -lxkbregistry"

###############################################################################
# 20. Wayland dependency staging
###############################################################################

#
# This directory is optional.
#
# If present, its libraries MUST be AArch64 glibc ELF libraries.
#
# It MUST NOT contain Android/Bionic libraries.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

_WLD="$PROJECT_ROOT/android/wayland-deps/usr"

if [ -d "$_WLD" ]; then

    echo
    echo "============================================================"
    echo " Staging Wayland dependencies"
    echo "============================================================"

    mkdir -p "$GLIBC_LIB/pkgconfig"
    mkdir -p "$GLIBC_INCLUDE"

    if [ -d "$_WLD/lib" ]; then
        cp -rn "$_WLD/lib/." "$GLIBC_LIB/" 2>/dev/null || true
    fi

    if [ -d "$_WLD/include" ]; then
        cp -rn "$_WLD/include/." "$GLIBC_INCLUDE/" 2>/dev/null || true
    fi

    if [ -d "$_WLD/share/pkgconfig" ]; then
        mkdir -p "$GLIBC_SHARE/pkgconfig"
        cp -rn \
            "$_WLD/share/pkgconfig/." \
            "$GLIBC_SHARE/pkgconfig/" \
            2>/dev/null || true
    fi

    echo "Wayland staging:"
    echo "  $_WLD"
    echo "  -> $GLIBC_PREFIX"

fi

###############################################################################
# 21. wayland-scanner
###############################################################################

if command -v wayland-scanner >/dev/null 2>&1; then

    export WAYLAND_SCANNER="$(command -v wayland-scanner)"

    echo
    echo "wayland-scanner:"
    echo "  $WAYLAND_SCANNER"

else

    echo
    echo "WARNING: wayland-scanner not found."
    echo "Wayland will only be enabled if explicitly requested and the build"
    echo "environment provides the required scanner."

fi

###############################################################################
# 22. Wayland configure mode
###############################################################################

WAYLAND_ARGS=(--without-wayland)

case "${ENABLE_WAYLAND:-auto}" in

    1|yes|true)

        WAYLAND_ARGS=(--with-wayland)

        ;;

    0|no|false)

        WAYLAND_ARGS=(--without-wayland)

        ;;

    auto)

        if command -v wayland-scanner >/dev/null 2>&1 &&
           [ -f "$GLIBC_LIB/libwayland-client.so" ]; then

            WAYLAND_ARGS=(--with-wayland)

        fi

        ;;

    *)

        echo
        echo "FATAL: invalid ENABLE_WAYLAND:"
        echo "  ${ENABLE_WAYLAND:-}"
        echo
        echo "Valid values:"
        echo "  auto"
        echo "  yes"
        echo "  no"
        exit 1

        ;;

esac

###############################################################################
# 23. Environment information
###############################################################################

echo
echo "============================================================"
echo " Target environment"
echo "============================================================"

echo "ARCH             = $ARCH"
echo "WIN_ARCH         = $WIN_ARCH"
echo "TARGET           = $TARGET"

echo
echo "TERMUX_PREFIX    = $TERMUX_PREFIX"
echo "GLIBC_ROOTFS     = $GLIBC_ROOTFS"
echo "GLIBC_PREFIX     = $GLIBC_PREFIX"
echo "RUNTIME_PATH     = $RUNTIME_PATH"
echo "INSTALL_DIR      = $install_dir"

echo
echo "OUTPUT_DIR       = $OUTPUT_DIR"
echo "TMPDIR           = $TMPDIR"

echo
echo "DISPLAY          = $DISPLAY"
echo "GDK_BACKEND      = $GDK_BACKEND"
echo "XDG_SESSION_TYPE = $XDG_SESSION_TYPE"

echo
echo "Wayland          = ${WAYLAND_ARGS[*]}"

echo
echo "LLVM-MinGW       = $LLVM_MINGW_TOOLCHAIN"

echo
echo "Host:"
uname -a

echo
echo "Compiler:"
"$GLIBC_CC" --version | head -1

echo
echo "C compiler command:"
echo "  $CC"

echo
echo "C++ compiler command:"
echo "  $CXX"

###############################################################################
# 24. Hard ABI checks
###############################################################################

#
# Refuse Android/Bionic compiler.
#

case "$GLIBC_CC" in

    *android*)

        echo
        echo "FATAL: GLIBC_CC is an Android/Bionic compiler:"
        echo "  $GLIBC_CC"
        exit 1

        ;;

esac

#
# Verify compiler target.
#

GLIBC_CC_TARGET="$("$GLIBC_CC" -dumpmachine 2>/dev/null || true)"

echo
echo "Compiler target:"
echo "  $GLIBC_CC_TARGET"

case "$GLIBC_CC_TARGET" in

    *android*)

        echo
        echo "FATAL: native compiler targets Android/Bionic:"
        echo "  $GLIBC_CC_TARGET"
        exit 1

        ;;

esac

#
# Required glibc staging directory.
#

if [ ! -d "$GLIBC_PREFIX" ]; then

    echo
    echo "FATAL: Termux glibc sysroot does not exist:"
    echo "  $GLIBC_PREFIX"
    exit 1

fi

#
# Required glibc loader.
#

if [ ! -f "$GLIBC_PREFIX/lib/ld-linux-aarch64.so.1" ]; then

    echo
    echo "FATAL: Termux glibc loader is missing:"
    echo "  $GLIBC_PREFIX/lib/ld-linux-aarch64.so.1"
    echo
    echo "The Termux glibc rootfs must be prepared before running this script."
    exit 1

fi

echo
echo "Termux glibc loader:"
echo "  OK"

###############################################################################
# 25. Check source tree
###############################################################################

cd "$PROJECT_ROOT"

if [ ! -f "./configure" ]; then

    echo
    echo "FATAL: Wine configure not found:"
    echo "  $PROJECT_ROOT/configure"
    exit 1

fi

###############################################################################
# 26. 16KB page support
###############################################################################

for arg in "$@"
do

    if [ "$arg" = "--enable-16kb-pages" ]; then

        echo
        echo "============================================================"
        echo " Enabling 16KB page-size linker alignment"
        echo "============================================================"

        #
        # Native glibc side:
        #
        # Do NOT define:
        #
        #   ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES
        #
        # globally.
        #

        export LDFLAGS="$LDFLAGS -Wl,-z,max-page-size=16384"

        #
        # Keep this only for PE-side source that explicitly expects it.
        #

        export CROSSCFLAGS="$CROSSCFLAGS -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES"

        echo "Native glibc linker:"
        echo "  max-page-size=16384"

        echo "PE compiler:"
        echo "  ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES"

    fi

done

###############################################################################
# 27. Android ntsync is NOT used
###############################################################################

for arg in "$@"
do

    if [ "$arg" = "--build-ntsync-android" ]; then

        echo
        echo "============================================================"
        echo " ERROR: Android ntsync is not valid"
        echo "============================================================"
        echo
        echo "This target uses:"
        echo "  Termux glibc"
        echo "  aarch64-linux-gnu"
        echo
        echo "It does not use Android/Bionic ntsync."
        echo
        exit 1

    fi

done

###############################################################################
# 28. Android sysvshm is NOT used
###############################################################################

for arg in "$@"
do

    if [ "$arg" = "--build-sysvshm" ]; then

        echo
        echo "============================================================"
        echo " ERROR: Android sysvshm is not valid"
        echo "============================================================"
        echo
        echo "Do NOT link:"
        echo "  -landroid-sysvshm"
        echo
        exit 1

    fi

done

###############################################################################
# 29. Configure
###############################################################################

for arg in "$@"
do

    if [ "$arg" = "--configure" ]; then

        echo
        echo "============================================================"
        echo " Configuring Wine ARM64EC"
        echo "============================================================"

        echo "Unix ABI:"
        echo "  $TARGET"

        echo
        echo "Windows architectures:"
        echo "  $WIN_ARCH"

        echo
        echo "Runtime:"
        echo "  Termux glibc"

        echo
        echo "Primary display:"
        echo "  Termux:X11"

        echo
        echo "Wayland:"
        echo "  ${WAYLAND_ARGS[*]}"

        echo

        rm -f config.cache

        ./configure \
          --enable-archs="$WIN_ARCH" \
          --host="$TARGET" \
          --prefix="$install_dir" \
          --bindir="$install_dir/bin" \
          --libdir="$install_dir/lib" \
          --exec-prefix="$install_dir" \
          --with-mingw=clang \
          --with-wine-tools=./wine-tools \
          --enable-win64 \
          --disable-win16 \
          --enable-nls \
          --disable-tests \
          \
          --with-alsa \
          --without-capi \
          --without-coreaudio \
          --without-cups \
          --without-dbus \
          --without-ffmpeg \
          --with-fontconfig \
          --with-freetype \
          --without-gcrypt \
          --without-gettext \
          --with-gettextpo=no \
          --without-gphoto \
          --with-gnutls \
          --without-gssapi \
          --with-gstreamer \
          --with-inotify \
          --without-krb5 \
          --without-netapi \
          --without-opencl \
          --with-opengl \
          --without-oss \
          --without-pcap \
          --without-pcsclite \
          --without-piper \
          --with-pthread \
          --with-pulse \
          --without-sane \
          --with-sdl \
          --without-udev \
          --without-unwind \
          --without-usb \
          --without-v4l2 \
          --without-vosk \
          --with-vulkan \
          "${WAYLAND_ARGS[@]}" \
          \
          --with-x \
          --without-xcomposite \
          --without-xfixes \
          --without-xinerama \
          --with-xrandr \
          --with-xrender \
          --without-xshape \
          --with-xshm \
          --without-xxf86vm

        echo
        echo "Wine configure completed."

        #######################################################################
        # 30. Apply patches
        #######################################################################

        echo
        echo "============================================================"
        echo " Applying patches"
        echo "============================================================"

        PATCHES=(

          "dlls_advapi32_advapi.c.patch"
          "dlls_amd_ags_x64_unixlib.c.patch"

          "dlls_dnsapi_libresolv.c.patch"
          "dlls_dnsapi_record.c.patch"

          "dlls_ws2_32_unixlib.c.patch"

          "dlls_gdiplus_region.c.patch"

          "dlls_xinput1_3_main.c.patch"

          "dlls_midimap_Makefile.in.patch"
          "dlls_midimap_midimap.c.patch"

          "dlls_nsiproxy.sys_nsi_common.h.patch"
          "dlls_nsiproxy.sys_ip.c.patch"
          "dlls_nsiproxy.sys_ndis.c.patch"

          "dlls_ntdll_Makefile.in.patch"
          "dlls_ntdll_unix_fsync.c.patch"
          "dlls_ntdll_unix_loader.c.patch"
          "dlls_ntdll_unix_server.c.patch"
          "dlls_ntdll_unix_sync.c.patch"
          "dlls_ntdll_unix_virtual.c.patch"

          "dlls_ntdll_unix_unix_private.h.patch"
          "dlls_wow64_virtual.c.patch"
          "include_wine_unixlib.h.patch"
          "include_winternl.h.patch"
          "dlls_ntdll_unix_signal_x86_64.c.patch"

          "dlls_opengl32_unix_wgl.c.patch"

          "dlls_shell32_shlfileop.c.patch"

          "dlls_user32_Makefile.in.patch"
          "dlls_win32u_clipboard.c.patch"

          "dlls_winebus.sys_bus_sdl.c.patch"
          "dlls_winepulse.drv_pulse.c.patch"

          "dlls_winex11.drv_bitblt.c.patch"
          "dlls_winex11.drv_keyboard.c.patch"
          "dlls_winex11.drv_mouse.c.patch"
          "dlls_winex11.drv_opengl.c.patch"
          "dlls_winex11.drv_window.c.patch"
          "dlls_winex11.drv_x11drv.h.patch"
          "dlls_winex11.drv_x11drv_main.c.patch"

          "dlls_wow64_syscall.c.patch"

          "loader_preloader.c.patch"

          "programs_explorer_desktop.c.patch"
          "programs_wineboot_wineboot.c.patch"
          "programs_winebrowser_Makefile.in.patch"
          "programs_winebrowser_main.c.patch"
          "programs_winemenubuilder_winemenubuilder.c.patch"

          "server_Makefile.in.patch"
          "server_fsync.c.patch"
          "server_inproc_sync.c.patch"
          "server_main.c.patch"
          "server_thread.c.patch"
          "server_unicode.c.patch"

          "dlls_ntdll_unix_esync.c.patch"
          "dlls_ntdll_unix_esync.h.patch"
          "server_esync.c.patch"
          "server_esync.h.patch"

          "ntsync_userspace.patch"
        )

        #######################################################################
        # Apply patch list
        #######################################################################

        for patch in "${PATCHES[@]}"; do

            echo "----------------------------------------"
            echo "Applying: $patch"

            if [ ! -f "./android/patches/$patch" ]; then

                echo
                echo "FATAL: patch does not exist:"
                echo "  ./android/patches/$patch"
                exit 1

            fi

            if git apply --check "./android/patches/$patch"; then

                git apply "./android/patches/$patch"

                echo "SUCCESS: $patch"

            else

                echo
                echo "FATAL: patch does not apply cleanly:"
                echo "  $patch"
                echo

                git apply --check "./android/patches/$patch" || true

                exit 1

            fi

        done

        echo
        echo "All glibc-compatible patches applied."

        #######################################################################
        # 31. /tmp handling
        #######################################################################

        echo
        echo "============================================================"
        echo " /tmp handling"
        echo "============================================================"

        echo
        echo "CI TMPDIR:"
        echo "  $TMPDIR"

        echo
        echo "Global /tmp source replacement:"
        echo "  DISABLED"

        #######################################################################
        # 32. Android source check
        #######################################################################

        echo
        echo "============================================================"
        echo " Checking Android-specific source guards"
        echo "============================================================"

        if grep -R \
            -n \
            --include='*.c' \
            --include='*.h' \
            --include='*.m4' \
            --include='Makefile.in' \
            '__ANDROID__' \
            dlls server loader \
            2>/dev/null |
            head -40
        then

            echo
            echo "NOTE: Android guards exist in source."
            echo "They are allowed when conditional and inactive on glibc."

        fi

        #######################################################################
        # 33. Critical source feature verification
        #######################################################################

        echo
        echo "============================================================"
        echo " Feature verification"
        echo "============================================================"

        verify_fail=0

        MARKERS=(

          "dlls/ntdll/unix/virtual.c|WINEVMEMMAXSIZE|WINEVMEMMAXSIZE"

          "dlls/ntdll/unix/sync.c|WINE_FAST_YIELD|fast yield"

          "dlls/ntdll/unix/esync.c|ESYNC_AUTO_EVENT|esync"

          "server/esync.c|esync: up and running|esync server"

          "server/inproc_sync.c|WINENTSYNC|userspace ntsync"

          "dlls/ntdll/unix/esync.c|ntsync_opt_in_active|ntsync esync gate"

          "dlls/ntdll/unix/sync.c|userspace_wait_objs|userspace ntsync wait"

          "dlls/gdiplus/region.c|if (x1_min <= x) x1_min = x + 1;|gdiplus"

          "dlls/ntdll/unix/loader.c|load_unixlib_by_name|FEX unixlib"

          "dlls/amd_ags_x64/unixlib.c|STATUS_NOT_IMPLEMENTED|AGS unix_call"

        )

        for row in "${MARKERS[@]}"; do

            m_file="${row%%|*}"
            rest="${row#*|}"

            m_token="${rest%%|*}"
            m_what="${rest#*|}"

            if [ -f "$m_file" ] &&
               grep -qF -- "$m_token" "$m_file"; then

                echo "  OK    $m_what"

            else

                echo "  FATAL $m_what"
                echo "        token: $m_token"
                echo "        file:  $m_file"

                verify_fail=1

            fi

        done

        if [ "$verify_fail" != "0" ]; then

            echo
            echo "FATAL: critical feature missing."
            echo "Refusing to build."
            exit 1

        fi

        echo
        echo "All critical features verified."

        #######################################################################
        # 34. GE-Proton patches
        #######################################################################

        if [ -d ./android/ge-patches/game-fixes ]; then

            echo
            echo "============================================================"
            echo " Applying GE-Proton patches"
            echo "============================================================"

            ./build-scripts/apply-ge-patches.sh

        fi

    fi

    ###########################################################################
    # 35. Build
    ###########################################################################

    if [ "$arg" = "--build" ]; then

        echo
        echo "============================================================"
        echo " Building Wine"
        echo "============================================================"

        rm -rf "$OUTPUT_DIR/bin"
        rm -rf "$OUTPUT_DIR/lib"
        rm -rf "$OUTPUT_DIR/share"

        rm -rf "$install_dir"

        mkdir -p "$OUTPUT_DIR"

        make -j"${JOBS:-$(nproc)}"

    fi

    ###########################################################################
    # 36. Install
    ###########################################################################

    if [ "$arg" = "--install" ]; then

        echo
        echo "============================================================"
        echo " Installing Wine"
        echo "============================================================"

        mkdir -p \
            "$OUTPUT_DIR/bin" \
            "$OUTPUT_DIR/lib" \
            "$OUTPUT_DIR/share"

        mkdir -p "$install_dir"

        make install -j"${JOBS:-$(nproc)}"

        #######################################################################
        # Wine binaries
        #######################################################################

        echo
        echo "Copying Wine binaries..."

        cp -r "$install_dir/bin/wine"* \
            "$OUTPUT_DIR/bin/" \
            2>/dev/null || true

        cp -r "$install_dir/bin/reg"* \
            "$OUTPUT_DIR/bin/" \
            2>/dev/null || true

        cp -r "$install_dir/bin/msi"* \
            "$OUTPUT_DIR/bin/" \
            2>/dev/null || true

        if [ -f "$install_dir/bin/notepad" ]; then
            cp "$install_dir/bin/notepad" "$OUTPUT_DIR/bin/"
        fi

        #######################################################################
        # Wine libraries
        #######################################################################

        if [ -d "$install_dir/lib/wine" ]; then

            cp -r \
                "$install_dir/lib/wine" \
                "$OUTPUT_DIR/lib/"

        else

            echo
            echo "FATAL: Wine library tree missing:"
            echo "  $install_dir/lib/wine"
            exit 1

        fi

        if [ -d "$install_dir/share/wine" ]; then

            cp -r \
                "$install_dir/share/wine" \
                "$OUTPUT_DIR/share/"

        fi

        #######################################################################
        # Wine Wayland
        #######################################################################

        echo
        echo "Checking Wine Wayland..."

        if find "$OUTPUT_DIR/lib/wine" \
            -type f \
            \( \
                -name 'winewayland.so' \
                -o -name 'winewayland.drv.so' \
                -o -name 'winewayland.drv' \
            \) \
            2>/dev/null |
            grep -q .
        then

            echo "Wine Wayland component detected."

        else

            if [ "${ENABLE_WAYLAND:-auto}" = "yes" ] ||
               [ "${ENABLE_WAYLAND:-auto}" = "true" ] ||
               [ "${ENABLE_WAYLAND:-auto}" = "1" ]; then

                echo
                echo "FATAL: Wayland was explicitly enabled but Wine Wayland"
                echo "       component was not built."
                exit 1

            fi

            echo "Wine Wayland not present."
            echo "This is allowed when Wayland is disabled."

        fi

        #######################################################################
        # Wine X11
        #######################################################################

        echo
        echo "Checking Wine X11..."

        if find "$OUTPUT_DIR/lib/wine" \
            -type f \
            \( \
                -name 'winex11.drv.so' \
                -o -name 'winex11.drv' \
            \) \
            2>/dev/null |
            grep -q .
        then

            echo "Wine X11 driver detected."

        else

            echo
            echo "FATAL: winex11.drv was not built."
            exit 1

        fi

        #######################################################################
        # AGS
        #######################################################################

        if ! ls "$OUTPUT_DIR"/lib/wine/*/amd_ags_x64.dll \
            >/dev/null 2>&1
        then

            echo
            echo "FATAL: amd_ags_x64.dll is not in the built layer."
            exit 1

        fi

        echo
        echo "amd_ags_x64.dll:"
        ls "$OUTPUT_DIR"/lib/wine/*/amd_ags_x64.dll

        #######################################################################
        # 37. Bundle optional Wayland runtime
        #######################################################################

        if [ -d "$_WLD/lib" ]; then

            echo
            echo "============================================================"
            echo " Bundling GLIBC Wayland runtime"
            echo "============================================================"

            for lib in \
                libwayland-client.so \
                libwayland-egl.so \
                libxkbcommon.so \
                libxkbregistry.so
            do

                if [ -f "$_WLD/lib/$lib" ]; then

                    cp -n \
                        "$_WLD/lib/$lib" \
                        "$OUTPUT_DIR/lib/" \
                        2>/dev/null || true

                    echo "Bundled: $lib"

                else

                    echo "WARNING: missing: $lib"

                fi

            done

            ###################################################################
            # libdrm
            ###################################################################

            if [ -f "$_WLD/lib/libdrm.so" ]; then

                cp -n \
                    "$_WLD/lib/libdrm.so" \
                    "$OUTPUT_DIR/lib/" \
                    2>/dev/null || true

            fi

            ###################################################################
            # Wayland Turnip
            ###################################################################

            if [ -f "$_WLD/lib/libvulkan_freedreno_wayland.so" ]; then

                mkdir -p "$OUTPUT_DIR/share/vulkan/icd.d"

                for v in \
                    "" \
                    "_a7xx" \
                    "_a8xx" \
                    "_a8xx_perf" \
                    "_a8xx_gen8" \
                    "_a8xx_smxz" \
                    "_a8xx_white" \
                    "_a8xx_upstream"
                do

                    if [ -f "$_WLD/lib/libvulkan_freedreno_wayland$v.so" ] &&
                       [ -f "$_WLD/share/vulkan/icd.d/banner_wayland_turnip$v.json" ]; then

                        cp \
                            "$_WLD/lib/libvulkan_freedreno_wayland$v.so" \
                            "$OUTPUT_DIR/lib/"

                        cp \
                            "$_WLD/share/vulkan/icd.d/banner_wayland_turnip$v.json" \
                            "$OUTPUT_DIR/share/vulkan/icd.d/"

                    else

                        echo
                        echo "FATAL: missing Wayland Turnip variant:"
                        echo "  $v"
                        echo
                        exit 1

                    fi

                done

                echo "Wayland Turnip ICDs bundled."

            fi

            ###################################################################
            # XKB data
            ###################################################################

            if [ -f "$_WLD/share/X11/xkb/rules/evdev.xml" ]; then

                mkdir -p "$OUTPUT_DIR/share/X11"

                cp -r \
                    "$_WLD/share/X11/xkb" \
                    "$OUTPUT_DIR/share/X11/"

                echo "Bundled xkeyboard-config."

            fi

            ###################################################################
            # Mesa EGL / Zink
            ###################################################################

            if [ -f "$_WLD/lib/libEGL.so.1" ]; then

                cp \
                    "$_WLD/lib/libEGL.so.1" \
                    "$OUTPUT_DIR/lib/" \
                    2>/dev/null || true

                if [ -f "$_WLD/lib/libGLESv2.so.2" ]; then

                    cp \
                        "$_WLD/lib/libGLESv2.so.2" \
                        "$OUTPUT_DIR/lib/" \
                        2>/dev/null || true

                fi

                cp \
                    "$_WLD/lib"/libgallium-*.so \
                    "$OUTPUT_DIR/lib/" \
                    2>/dev/null || true

                echo "Bundled Mesa EGL/Zink."

            fi

        fi

        #######################################################################
        # 38. X11 runtime libraries
        #######################################################################

        if [ -d "$_WLD/lib" ]; then

            for lib in \
                libX11.so \
                libXext.so \
                libXrender.so \
                libXrandr.so \
                libXfixes.so \
                libXdamage.so \
                libXcomposite.so \
                libXinerama.so \
                libXcursor.so \
                libXi.so \
                libXxf86vm.so \
                libxcb.so \
                libXau.so \
                libXdmcp.so
            do

                if [ -f "$_WLD/lib/$lib" ]; then

                    cp -n \
                        "$_WLD/lib/$lib" \
                        "$OUTPUT_DIR/lib/" \
                        2>/dev/null || true

                fi

            done

        fi

        #######################################################################
        # 39. Strip
        #######################################################################

        echo
        echo "============================================================"
        echo " Stripping binaries"
        echo "============================================================"

        before_mb=$(du -sm "$OUTPUT_DIR" 2>/dev/null | cut -f1)

        if [ "${UNSTRIPPED:-0}" = "1" ] ||
           [ "${UNSTRIPPED:-false}" = "true" ]; then

            echo
            echo "UNSTRIPPED enabled."
            echo "Keeping debug symbols."

        else

            find "$OUTPUT_DIR/lib" "$OUTPUT_DIR/bin" \
                -type f \
                \( \
                    -name '*.dll' \
                    -o -name '*.exe' \
                    -o -name '*.drv' \
                    -o -name '*.so' \
                    -o -name 'wine' \
                    -o -name 'wine-preloader' \
                \) \
                -print0 \
                2>/dev/null |
            while IFS= read -r -d '' f
            do

                #
                # Keep normal symbols required for practical debugging.
                # Do not use --strip-all here.
                #

                "$STRIP" --strip-debug "$f" 2>/dev/null || true

            done

        fi

        after_mb=$(du -sm "$OUTPUT_DIR" 2>/dev/null | cut -f1)

        echo
        echo "OUTPUT tree:"
        echo "  ${before_mb}MB -> ${after_mb}MB"

        #######################################################################
        # 40. Wine symlinks
        #######################################################################

        mkdir -p "$install_dir/bin"

        if [ -f "$OUTPUT_DIR/lib/wine/aarch64-unix/wine" ]; then

            ln -sf \
                ../lib/wine/aarch64-unix/wine \
                "$install_dir/bin/wine"

            ln -sf \
                ../lib/wine/aarch64-unix/wine \
                "$OUTPUT_DIR/bin/wine"

        else

            echo
            echo "FATAL: native Wine binary missing:"
            echo "  $OUTPUT_DIR/lib/wine/aarch64-unix/wine"
            exit 1

        fi

        if [ -f "$OUTPUT_DIR/lib/wine/aarch64-unix/wine-preloader" ]; then

            ln -sf \
                ../lib/wine/aarch64-unix/wine-preloader \
                "$OUTPUT_DIR/bin/wine-preloader"

            ln -sf \
                ../lib/wine/aarch64-unix/wine-preloader \
                "$install_dir/bin/wine-preloader"

        fi

        echo
        echo "Wine loader symlinks:"

        ls -la \
            "$OUTPUT_DIR/bin/wine" \
            2>/dev/null || true

        ls -la \
            "$OUTPUT_DIR/bin/wine-preloader" \
            2>/dev/null || true

        #######################################################################
        # 41. Termux:X11 launcher
        #######################################################################

        cat > "$OUTPUT_DIR/bin/wine-termux-x11" <<'EOF'
#!/system/bin/sh

TERMUX_PREFIX="/data/data/com.termux/files/usr"
GLIBC_PREFIX="$TERMUX_PREFIX/glibc"
WINE_PREFIX="$GLIBC_PREFIX/opt/wine"

export DISPLAY="${DISPLAY:-:0}"

export GDK_BACKEND="${GDK_BACKEND:-x11}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"

export TERMUX_X11_FORCE_FLIP="${TERMUX_X11_FORCE_FLIP:-1}"

export TMPDIR="${TERMUX_PREFIX}/tmp/runtime"
export TMP="$TMPDIR"
export TEMP="$TMPDIR"

export LD_LIBRARY_PATH="$WINE_PREFIX/lib:$GLIBC_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

export PATH="$WINE_PREFIX/bin:$PATH"

exec "$WINE_PREFIX/bin/wine" "$@"
EOF

        chmod +x "$OUTPUT_DIR/bin/wine-termux-x11"

        #######################################################################
        # 42. Runtime environment
        #######################################################################

        cat > "$OUTPUT_DIR/glibc-env.sh" <<EOF
export TERMUX_PREFIX="$TERMUX_PREFIX"

# Android runtime path.
export GLIBC_PREFIX="$RUNTIME_PATH"

# Wine runtime path.
export WINE_PREFIX="$RUNTIME_PATH/opt/wine"

export DISPLAY="\${DISPLAY:-:0}"
export GDK_BACKEND="\${GDK_BACKEND:-x11}"
export XDG_SESSION_TYPE="\${XDG_SESSION_TYPE:-x11}"
export TERMUX_X11_FORCE_FLIP="\${TERMUX_X11_FORCE_FLIP:-1}"

export TMPDIR="\${TMPDIR:-\$TERMUX_PREFIX/tmp/runtime}"
export TMP="\$TMPDIR"
export TEMP="\$TMPDIR"

export LD_LIBRARY_PATH="\$WINE_PREFIX/lib:\$GLIBC_PREFIX/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"

export PATH="\$WINE_PREFIX/bin:\$PATH"
EOF

        #######################################################################
        # 43. Build information
        #######################################################################

        cat > "$OUTPUT_DIR/build-info.txt" <<EOF
Wine / Proton ARM64EC
=====================

Native Unix ABI:
  AArch64 GNU/Linux glibc

Native target:
  $TARGET

Windows architectures:
  arm64ec
  aarch64
  i386

CI staging root:
  $GLIBC_ROOTFS

CI glibc prefix:
  $GLIBC_PREFIX

Android runtime glibc:
  $RUNTIME_PATH

Wine runtime:
  $RUNTIME_PATH/opt/wine

Primary display:
  Termux:X11

DISPLAY:
  :0

GDK_BACKEND:
  x11

Wayland configure:
  ${WAYLAND_ARGS[*]}

Android/Bionic native compiler:
  NO

Android NDK:
  NOT USED

Android ntsync:
  NOT USED

Android sysvshm:
  NOT USED

LLVM-MinGW:
  $LLVM_MINGW_TOOLCHAIN

LLVM-MinGW clang:
  $LLVM_MINGW_TOOLCHAIN/clang
EOF

        #######################################################################
        # 44. Final ELF verification
        #######################################################################

        echo
        echo "============================================================"
        echo " Final ELF verification"
        echo "============================================================"

        WINE_ELF="$OUTPUT_DIR/lib/wine/aarch64-unix/wine"

        if [ -e "$WINE_ELF" ]; then

            echo
            echo "Wine ELF:"
            file "$WINE_ELF" || true

            echo
            echo "Wine machine:"
            readelf -h "$WINE_ELF" 2>/dev/null |
                grep -E 'Class:|Machine:' ||
                true

            echo
            echo "Wine NEEDED:"
            readelf -d "$WINE_ELF" 2>/dev/null |
                grep NEEDED ||
                true

            echo
            echo "Wine interpreter:"
            readelf -l "$WINE_ELF" 2>/dev/null |
                grep "Requesting program interpreter" ||
                true

            echo
            echo "Wine RPATH/RUNPATH:"
            readelf -d "$WINE_ELF" 2>/dev/null |
                grep -E 'RPATH|RUNPATH' ||
                true

            echo
            echo "Checking CI path leakage..."

            if readelf -d "$WINE_ELF" 2>/dev/null |
                grep -F "$GLIBC_ROOTFS" >/dev/null 2>&1
            then

                echo
                echo "FATAL: CI staging path leaked into Wine ELF:"
                echo "  $GLIBC_ROOTFS"
                exit 1

            fi

            echo "No CI staging path found in Wine ELF."

            echo
            echo "Checking Android runtime path..."

            if readelf -d "$WINE_ELF" 2>/dev/null |
                grep -F "$RUNTIME_PATH" >/dev/null 2>&1
            then

                echo "Runtime path detected:"
                echo "  $RUNTIME_PATH"

            else

                echo "WARNING: runtime path not present in dynamic section."

            fi

        else

            echo
            echo "FATAL: native Wine ELF missing:"
            echo "  $WINE_ELF"
            exit 1

        fi

        #######################################################################
        # 45. Final layer verification
        #######################################################################

        echo
        echo "============================================================"
        echo " Final ARM64EC layer verification"
        echo "============================================================"

        fail=0

        check_file()
        {
            if [ -f "$1" ]; then
                echo "OK   $1"
            else
                echo "FAIL $1"
                fail=1
            fi
        }

        #######################################################################
        # Native Wine
        #######################################################################

        check_file \
            "$OUTPUT_DIR/lib/wine/aarch64-unix/wine"

        #######################################################################
        # X11
        #######################################################################

        if find "$OUTPUT_DIR/lib/wine" \
            -type f \
            \( \
                -name 'winex11.drv.so' \
                -o -name 'winex11.drv' \
            \) \
            2>/dev/null |
            grep -q .
        then

            echo "OK   winex11.drv"

        else

            echo "FAIL winex11.drv"
            fail=1

        fi

        #######################################################################
        # Wayland
        #######################################################################

        if find "$OUTPUT_DIR/lib/wine" \
            -type f \
            \( \
                -name 'winewayland.so' \
                -o -name 'winewayland.drv.so' \
                -o -name 'winewayland.drv' \
            \) \
            2>/dev/null |
            grep -q .
        then

            echo "OK   Wine Wayland"

        else

            echo "WARNING Wine Wayland not found"

        fi

        #######################################################################
        # AGS
        #######################################################################

        if ls "$OUTPUT_DIR"/lib/wine/*/amd_ags_x64.dll \
            >/dev/null 2>&1
        then

            echo "OK   amd_ags_x64.dll"

        else

            echo "FAIL amd_ags_x64.dll"
            fail=1

        fi

        #######################################################################
        # Runtime launcher
        #######################################################################

        check_file \
            "$OUTPUT_DIR/bin/wine-termux-x11"

        check_file \
            "$OUTPUT_DIR/glibc-env.sh"

        check_file \
            "$OUTPUT_DIR/build-info.txt"

        #######################################################################
        # Final result
        #######################################################################

        if [ "$fail" != "0" ]; then

            echo
            echo "============================================================"
            echo " FATAL: layer verification failed"
            echo "============================================================"
            exit 1

        fi

        echo
        echo "============================================================"
        echo " BUILD LAYER READY"
        echo "============================================================"

        echo
        echo "Output:"
        echo "  $OUTPUT_DIR"

        echo
        echo "Termux:X11 launcher:"
        echo "  $OUTPUT_DIR/bin/wine-termux-x11"

        echo
        echo "Runtime environment:"
        echo "  $OUTPUT_DIR/glibc-env.sh"

        echo
        echo "Android runtime:"
        echo "  $RUNTIME_PATH/opt/wine"

    fi

done
