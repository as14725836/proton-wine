#!/bin/bash

# Fail hard on any command error.
set -eo pipefail

###############################################################################
# Wine / Proton ARM64EC
#
# TARGET:
#   GameNative
#   Termux glibc
#   termux-x11
#   ARM64EC Proton 11.0-1
#
# ABI:
#
#   Unix/native side:
#       AArch64 GNU/Linux glibc
#       aarch64-linux-gnu
#
#   Windows/PE side:
#       arm64ec
#       aarch64
#       i386
#       LLVM-MinGW
#
# DISPLAY:
#       termux-x11 :0 = PRIMARY
#       Wayland       = OPTIONAL
#
###############################################################################

###############################################################################
# 0. Basic target
###############################################################################

export ARCH="aarch64"
export WIN_ARCH="arm64ec,aarch64,i386"

export OUTPUT_DIR="$HOME/compiled-files-aarch64"

###############################################################################
# 1. Termux glibc filesystem
###############################################################################

#
# Normal Termux/Bionic:
#
#   /data/data/com.termux/files/usr
#
# Termux glibc:
#
#   /data/data/com.termux/files/usr/glibc
#
# DO NOT use the normal Termux lib/include tree for the glibc Wine Unix side.
#

export TERMUX_PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"

export GLIBC_PREFIX="${GLIBC_PREFIX:-$TERMUX_PREFIX/glibc}"

export GLIBC_LIB="$GLIBC_PREFIX/lib"
export GLIBC_INCLUDE="$GLIBC_PREFIX/include"
export GLIBC_SHARE="$GLIBC_PREFIX/share"
export GLIBC_ETC="$GLIBC_PREFIX/etc"

export deps="$GLIBC_PREFIX"

export RUNTIME_PATH="$GLIBC_PREFIX"

export install_dir="$GLIBC_PREFIX/opt/wine"

###############################################################################
# 2. Runtime temporary directory
###############################################################################

#
# Do NOT globally modify Wine source from /tmp -> Termux path.
#
# Wine/runtime code should use TMPDIR.
#

export TERMUX_TMPDIR="$TERMUX_PREFIX/tmp/runtime"

mkdir -p "$TERMUX_TMPDIR"

export TMPDIR="$TERMUX_TMPDIR"
export TMP="$TERMUX_TMPDIR"
export TEMP="$TERMUX_TMPDIR"

###############################################################################
# 3. Display
###############################################################################

#
# GameNative target is Termux:X11.
#
# Do not force Wayland globally.
#

export DISPLAY="${DISPLAY:-:0}"

export GDK_BACKEND="${GDK_BACKEND:-x11}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"

export TERMUX_X11_FORCE_FLIP="${TERMUX_X11_FORCE_FLIP:-1}"

###############################################################################
# 4. Unix target
###############################################################################

#
# IMPORTANT:
#
# OLD:
#
#   TARGET=aarch64-linux-android28
#
# NEW:
#
#   TARGET=aarch64-linux-gnu
#
# This is the main Bionic -> glibc change.
#

export TARGET="${TARGET:-aarch64-linux-gnu}"

###############################################################################
# 5. Build compiler
###############################################################################

#
# Preferred CI runner:
#
#   ubuntu-24.04-arm
#
# Then the runner itself is:
#
#   aarch64 + Ubuntu glibc
#
# This lets us compile the Wine Unix side natively.
#
# If you run this script on x86_64, set:
#
#   GLIBC_TOOLCHAIN=/path/to/aarch64-linux-gnu-toolchain
#
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
# LLVM-MinGW remains the Windows PE compiler.
#
# It is NOT used as the Unix glibc compiler.
#

export LLVM_MINGW_TOOLCHAIN="$HOME/toolchains/llvm-mingw-20250920-ucrt-ubuntu-22.04-x86_64/bin"

if [ ! -d "$LLVM_MINGW_TOOLCHAIN" ]; then
    echo "FATAL: LLVM-MinGW not found:"
    echo "  $LLVM_MINGW_TOOLCHAIN"
    exit 1
fi

export PATH="$LLVM_MINGW_TOOLCHAIN:$PATH"

###############################################################################
# 7. ccache
###############################################################################

if command -v ccache >/dev/null 2>&1; then

    export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"

    ccache -M 3G >/dev/null 2>&1 || true

    mkdir -p "$HOME/ccache-bin"

    #
    # Native glibc compiler.
    #
    # Use wrapper names for Wine configure/build.
    #

    ln -sf "$(command -v ccache)" "$HOME/ccache-bin/gcc"
    ln -sf "$(command -v ccache)" "$HOME/ccache-bin/g++"

    export PATH="$HOME/ccache-bin:$PATH"

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

#
# DLLTOOL belongs to LLVM-MinGW / PE side.
#

export DLLTOOL="$LLVM_MINGW_TOOLCHAIN/llvm-dlltool"

###############################################################################
# 8. Compiler flags
###############################################################################

export C_OPTS="-g0 -O2 -Wno-declaration-after-statement -Wno-implicit-function-declaration -Wno-int-conversion"

export CFLAGS="$C_OPTS"
export CXXFLAGS="$C_OPTS"

#
# ARM64EC PE side.
#

export CROSSCFLAGS="-g0 -O2"

###############################################################################
# 9. glibc sysroot
###############################################################################

#
# DO NOT use Android NDK sysroot.
#

export CPPFLAGS="-I$GLIBC_INCLUDE"

export LDFLAGS="-L$GLIBC_LIB \
-Wl,-rpath,$GLIBC_LIB \
-Wl,-rpath,$GLIBC_PREFIX/opt/wine/lib"

###############################################################################
# 10. pkg-config
###############################################################################

#
# Do not allow normal Termux/Bionic .pc files to leak into the build.
#

export PKG_CONFIG_SYSROOT_DIR="$GLIBC_PREFIX"

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
# PRIMARY runtime backend:
#
#   Wine -> winex11.drv -> X11 client libraries -> Termux:X11 :0
#
# These MUST be glibc-compatible X11 libraries.
#
# Do NOT use:
#
#   $TERMUX_PREFIX/lib
#
# if that directory contains Bionic libraries.
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

#
# Wayland is OPTIONAL.
#
# Termux:X11 remains the default.
#
# The Wayland libraries here MUST be glibc-compatible.
#

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
# android/wayland-deps/usr is now expected to contain GLIBC-compatible
# AArch64 libraries.
#
# It MUST NOT contain Bionic Android libraries.
#

_WLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/android/wayland-deps/usr"

if [ -d "$_WLD" ]; then

    mkdir -p "$GLIBC_LIB/pkgconfig"
    mkdir -p "$GLIBC_INCLUDE"

    cp -rn "$_WLD/lib/." "$GLIBC_LIB/" 2>/dev/null || true
    cp -rn "$_WLD/include/." "$GLIBC_INCLUDE/" 2>/dev/null || true

    if [ -d "$_WLD/share/pkgconfig" ]; then
        mkdir -p "$GLIBC_SHARE/pkgconfig"
        cp -rn "$_WLD/share/pkgconfig/." "$GLIBC_SHARE/pkgconfig/" 2>/dev/null || true
    fi

    echo "Staged GLIBC Wayland/XKB dependencies into:"
    echo "  $GLIBC_PREFIX"

fi

###############################################################################
# 21. wayland-scanner
###############################################################################

if command -v wayland-scanner >/dev/null 2>&1; then

    export WAYLAND_SCANNER="$(command -v wayland-scanner)"

    echo "wayland-scanner:"
    echo "  $WAYLAND_SCANNER"

else

    echo "WARNING: wayland-scanner not found."
    echo "Install host Wayland development tools."

fi

###############################################################################
# 22. Verify glibc environment
###############################################################################

echo
echo "============================================================"
echo " Target environment"
echo "============================================================"

echo "ARCH             = $ARCH"
echo "WIN_ARCH         = $WIN_ARCH"
echo "TARGET           = $TARGET"
echo "GLIBC_PREFIX     = $GLIBC_PREFIX"
echo "INSTALL_DIR      = $install_dir"
echo "OUTPUT_DIR       = $OUTPUT_DIR"
echo "DISPLAY          = $DISPLAY"
echo "TMPDIR           = $TMPDIR"
echo

echo "Host:"
uname -a

echo
echo "Compiler:"
$GLIBC_CC --version | head -1

###############################################################################
# 23. Hard ABI checks
###############################################################################

#
# Refuse accidental Android/Bionic compiler.
#

case "$GLIBC_CC" in
    *android*)
        echo
        echo "FATAL: GLIBC_CC is an Android/Bionic compiler:"
        echo "$GLIBC_CC"
        exit 1
        ;;
esac

case "$TARGET" in
    *android*)
        echo
        echo "FATAL: TARGET is still Android/Bionic:"
        echo "$TARGET"
        exit 1
        ;;
esac

if [ ! -d "$GLIBC_PREFIX" ]; then
    echo
    echo "FATAL: Termux glibc sysroot does not exist:"
    echo "  $GLIBC_PREFIX"
    exit 1
fi

if [ ! -f "$GLIBC_PREFIX/lib/ld-linux-aarch64.so.1" ]; then
    echo
    echo "WARNING: glibc loader not found in staged sysroot:"
    echo "  $GLIBC_PREFIX/lib/ld-linux-aarch64.so.1"
    echo
fi

###############################################################################
# 24. Check source tree
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

if [ ! -f "./configure" ]; then
    echo
    echo "FATAL: Wine configure not found:"
    echo "  $PROJECT_ROOT/configure"
    exit 1
fi

###############################################################################
# 25. 16KB page support
###############################################################################

for arg in "$@"
do

    if [ "$arg" == "--enable-16kb-pages" ]; then

        echo "Enabling 16KB page-size compatible linker alignment..."

        #
        # IMPORTANT:
        #
        # Do NOT define:
        #
        #   ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES
        #
        # on glibc.
        #
        # That macro is Android-specific.
        #

        export LDFLAGS="$LDFLAGS -Wl,-z,max-page-size=16384"

        #
        # Keep the PE-side compile define only if the downstream source
        # actually tests it. This is not used as a glibc ABI define.
        #

        export CROSSCFLAGS="$CROSSCFLAGS -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES"

        echo "16KB page-size linker alignment enabled."

    fi

done

###############################################################################
# 26. Android ntsync is NOT used
###############################################################################

for arg in "$@"
do

    if [ "$arg" == "--build-ntsync-android" ]; then

        echo
        echo "============================================================"
        echo " ERROR: --build-ntsync-android is not valid for glibc build"
        echo "============================================================"
        echo
        echo "This target is Termux glibc."
        echo
        echo "Android/Bionic:"
        echo "  aarch64-linux-android"
        echo
        echo "glibc:"
        echo "  aarch64-linux-gnu"
        echo
        echo "Use userspace ntsync.patch instead."
        echo

        exit 1

    fi

done

###############################################################################
# 27. android_sysvshm is NOT used
###############################################################################

for arg in "$@"
do

    if [ "$arg" == "--build-sysvshm" ]; then

        echo
        echo "============================================================"
        echo " ERROR: --build-sysvshm is an Android/Bionic component"
        echo "============================================================"
        echo
        echo "The glibc build uses normal glibc X11/XShm libraries."
        echo
        echo "Do NOT link:"
        echo "  -landroid-sysvshm"
        echo

        exit 1

    fi

done

###############################################################################
# 28. Configure
###############################################################################

for arg in "$@"
do

    if [ "$arg" == "--configure" ]; then

        echo
        echo "============================================================"
        echo " Configuring Wine ARM64EC"
        echo "============================================================"

        echo "Unix ABI:"
        echo "  $TARGET"

        echo "Windows:"
        echo "  $WIN_ARCH"

        echo "Runtime:"
        echo "  Termux glibc"

        echo "Display:"
        echo "  termux-x11"

        echo "Wayland:"
        echo "  enabled / optional"

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
          --with-wayland \
          \
          --with-x \
          --without-xcomposite \
          --without-xfixes \
          --without-xinerama \
          --with-xrandr \
          --with-xrender \
          --without-xshape \
          --with-xshm \
          --without-xxf86vm \
          || exit $?

        echo
        echo "Wine configure completed."

        #######################################################################
        # 29. Apply patches
        #######################################################################

        echo
        echo "============================================================"
        echo " Applying patches"
        echo "============================================================"

        #
        # IMPORTANT:
        #
        # These are the patches from your original script.
        #
        # Android-only patches have been separated/removed below.
        #
        #######################################################################

        PATCHES=(

          #####################################################################
          # Core
          #####################################################################

          "dlls_advapi32_advapi.c.patch"
          "dlls_amd_ags_x64_unixlib.c.patch"

          #####################################################################
          # DNS
          #
          # NOTE:
          # The original comments described some of these as Bionic-specific.
          # Keep them only if the patch itself has a generic/glibc-safe guard.
          #####################################################################

          "dlls_dnsapi_libresolv.c.patch"
          "dlls_dnsapi_record.c.patch"

          #####################################################################
          # Winsock
          #####################################################################

          "dlls_ws2_32_unixlib.c.patch"

          #####################################################################
          # gdiplus
          #####################################################################

          "dlls_gdiplus_region.c.patch"

          #####################################################################
          # xinput
          #####################################################################

          "dlls_xinput1_3_main.c.patch"

          #####################################################################
          # midi
          #####################################################################

          "dlls_midimap_Makefile.in.patch"
          "dlls_midimap_midimap.c.patch"

          #####################################################################
          # nsiproxy
          #
          # These must be checked because your original version contains
          # Android networking assumptions.
          #####################################################################

          "dlls_nsiproxy.sys_nsi_common.h.patch"
          "dlls_nsiproxy.sys_ip.c.patch"
          "dlls_nsiproxy.sys_ndis.c.patch"

          #####################################################################
          # ntdll
          #####################################################################

          "dlls_ntdll_Makefile.in.patch"
          "dlls_ntdll_unix_fsync.c.patch"
          "dlls_ntdll_unix_loader.c.patch"
          "dlls_ntdll_unix_server.c.patch"
          "dlls_ntdll_unix_sync.c.patch"
          "dlls_ntdll_unix_virtual.c.patch"

          #####################################################################
          # DO NOT include:
          #
          # dlls_ntdll_unix_env.c.patch
          #
          # The original comment explicitly says:
          #
          #   Android bionic locale bring-up
          #
          # That is not required on glibc.
          #####################################################################

          #####################################################################
          # FEX / Unixlib
          #####################################################################

          "dlls_ntdll_unix_unix_private.h.patch"
          "dlls_wow64_virtual.c.patch"
          "include_wine_unixlib.h.patch"
          "include_winternl.h.patch"
          "dlls_ntdll_unix_signal_x86_64.c.patch"

          #####################################################################
          # OpenGL
          #####################################################################

          "dlls_opengl32_unix_wgl.c.patch"

          #####################################################################
          # shell32
          #####################################################################

          "dlls_shell32_shlfileop.c.patch"

          #####################################################################
          # clipboard
          #####################################################################

          "dlls_user32_Makefile.in.patch"
          "dlls_win32u_clipboard.c.patch"

          #####################################################################
          # drivers
          #####################################################################

          "dlls_winebus.sys_bus_sdl.c.patch"
          "dlls_winepulse.drv_pulse.c.patch"

          #####################################################################
          # winex11
          #
          # PRIMARY display path for Termux:X11.
          #####################################################################

          "dlls_winex11.drv_bitblt.c.patch"
          "dlls_winex11.drv_keyboard.c.patch"
          "dlls_winex11.drv_mouse.c.patch"
          "dlls_winex11.drv_opengl.c.patch"
          "dlls_winex11.drv_window.c.patch"
          "dlls_winex11.drv_x11drv.h.patch"
          "dlls_winex11.drv_x11drv_main.c.patch"

          #####################################################################
          # WOW64 / ARM64EC
          #####################################################################

          "dlls_wow64_syscall.c.patch"

          #####################################################################
          # loader
          #####################################################################

          "loader_preloader.c.patch"

          #####################################################################
          # programs
          #####################################################################

          "programs_explorer_desktop.c.patch"
          "programs_wineboot_wineboot.c.patch"
          "programs_winebrowser_Makefile.in.patch"
          "programs_winebrowser_main.c.patch"
          "programs_winemenubuilder_winemenubuilder.c.patch"

          #####################################################################
          # server
          #####################################################################

          "server_Makefile.in.patch"
          "server_fsync.c.patch"
          "server_inproc_sync.c.patch"
          "server_main.c.patch"
          "server_thread.c.patch"
          "server_unicode.c.patch"

          #####################################################################
          # esync
          #####################################################################

          "dlls_ntdll_unix_esync.c.patch"
          "dlls_ntdll_unix_esync.h.patch"
          "server_esync.c.patch"
          "server_esync.h.patch"

          #####################################################################
          # userspace ntsync
          #
          # This is NOT android ntsync.
          #
          # It is the userspace fallback and can be used by glibc.
          #####################################################################

          "ntsync_userspace.patch"
        )

        #######################################################################
        # Apply patch list
        #######################################################################

        for patch in "${PATCHES[@]}"; do

            echo "----------------------------------------"
            echo "Applying: $patch"

            if [ ! -f "./android/patches/$patch" ]; then

                echo "FATAL: ./android/patches/$patch does not exist"
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
        # 30. IMPORTANT: no global /tmp replacement
        #######################################################################

        echo
        echo "============================================================"
        echo " /tmp handling"
        echo "============================================================"

        echo
        echo "Using:"
        echo "  TMPDIR=$TMPDIR"

        echo
        echo "Global /tmp source replacement is DISABLED."
        echo "Wine runtime uses TMPDIR instead."

        #######################################################################
        # 31. Verify Android-specific code did not leak into native build
        #######################################################################

        echo
        echo "============================================================"
        echo " Checking native source for accidental Bionic logic"
        echo "============================================================"

        #
        # These are warnings rather than hard errors because some Proton
        # sources legitimately contain Android guards for PE/build portability.
        #

        if grep -R \
            -n \
            --include='*.c' \
            --include='*.h' \
            --include='*.m4' \
            --include='Makefile.in' \
            '__ANDROID__' \
            dlls server loader \
            2>/dev/null \
            | head -40
        then

            echo
            echo "NOTE: Android guards exist in the source."
            echo "They are allowed when conditional and inactive on glibc."

        fi

        #######################################################################
        # 32. Verify critical source features
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

            if [ -f "$m_file" ] && grep -qF -- "$m_token" "$m_file"; then

                echo "  OK    $m_what"

            else

                echo "  FATAL $m_what"
                echo "        $m_token"
                echo "        $m_file"

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
        # 33. GE-Proton patches
        #######################################################################

        if [ -d ./android/ge-patches/game-fixes ]; then

            echo
            echo "============================================================"
            echo " Applying GE-Proton patches"
            echo "============================================================"

            ./build-scripts/apply-ge-patches.sh || exit $?

        fi

    fi

    ###########################################################################
    # 34. Build
    ###########################################################################

    if [ "$arg" == "--build" ]; then

        echo
        echo "============================================================"
        echo " Building Wine"
        echo "============================================================"

        rm -rf "$OUTPUT_DIR/bin"
        rm -rf "$OUTPUT_DIR/lib"
        rm -rf "$OUTPUT_DIR/share"

        rm -rf "$install_dir"

        mkdir -p "$OUTPUT_DIR"

        make -j"${JOBS:-$(nproc)}" || exit $?

    fi

    ###########################################################################
    # 35. Install
    ###########################################################################

    if [ "$arg" == "--install" ]; then

        echo
        echo "============================================================"
        echo " Installing Wine"
        echo "============================================================"

        mkdir -p "$OUTPUT_DIR/bin"
        mkdir -p "$OUTPUT_DIR/lib"
        mkdir -p "$OUTPUT_DIR/share"

        mkdir -p "$install_dir"

        make install -j"${JOBS:-$(nproc)}" || exit $?

        #######################################################################
        # Copy basic binaries
        #######################################################################

        echo "Copying Wine binaries..."

        cp -r "$install_dir/bin/wine"* "$OUTPUT_DIR/bin/" 2>/dev/null || true
        cp -r "$install_dir/bin/reg"* "$OUTPUT_DIR/bin/" 2>/dev/null || true
        cp -r "$install_dir/bin/msi"* "$OUTPUT_DIR/bin/" 2>/dev/null || true

        [ -f "$install_dir/bin/notepad" ] && \
            cp "$install_dir/bin/notepad" "$OUTPUT_DIR/bin/"

        #######################################################################
        # Copy Wine library tree
        #######################################################################

        cp -r "$install_dir/lib/wine" "$OUTPUT_DIR/lib"

        cp -r "$install_dir/share/wine" "$OUTPUT_DIR/share"

        #######################################################################
        # Wine Wayland verification
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
            2>/dev/null | grep -q .; then

            echo "Wine Wayland component detected."

        else

            echo
            echo "WARNING: Wine Wayland component not found."

        fi

        #######################################################################
        # Wine X11 verification
        #######################################################################

        echo
        echo "Checking Wine X11..."

        if find "$OUTPUT_DIR/lib/wine" \
            -type f \
            \( \
              -name 'winex11.drv.so' \
              -o -name 'winex11.drv' \
            \) \
            2>/dev/null | grep -q .; then

            echo "Wine X11 driver detected."

        else

            echo
            echo "FATAL: winex11.drv was not built."
            exit 1

        fi

        #######################################################################
        # AGS
        #######################################################################

        if ! ls "$OUTPUT_DIR"/lib/wine/*/amd_ags_x64.dll >/dev/null 2>&1; then

            echo
            echo "FATAL: amd_ags_x64.dll is not in the built layer."
            echo

            exit 1

        fi

        echo "amd_ags_x64.dll present:"
        ls "$OUTPUT_DIR"/lib/wine/*/amd_ags_x64.dll

        #######################################################################
        # Wayland runtime
        #######################################################################

        _WLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/android/wayland-deps/usr"

        if [ -d "$_WLD/lib" ]; then

            echo
            echo "============================================================"
            echo " Bundling GLIBC Wayland runtime"
            echo "============================================================"

            #
            # These must be GLIBC libraries.
            #

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

                    so="$ _WLD"

                    if [ -f "$_WLD/libvulkan_freedreno_wayland$v.so" ] && \
                       [ -f "$_WLD/../share/vulkan/icd.d/banner_wayland_turnip$v.json" ]; then

                        cp \
                            "$_WLD/libvulkan_freedreno_wayland$v.so" \
                            "$OUTPUT_DIR/lib/"

                        cp \
                            "$_WLD/../share/vulkan/icd.d/banner_wayland_turnip$v.json" \
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

                cp \
                    "$_WLD/lib/libGLESv2.so.2" \
                    "$OUTPUT_DIR/lib/" \
                    2>/dev/null || true

                cp \
                    "$_WLD"/libgallium-*.so \
                    "$OUTPUT_DIR/lib/" \
                    2>/dev/null || true

                echo "Bundled Mesa EGL/Zink."

            fi

        fi

        #######################################################################
        # X11 runtime libraries
        #######################################################################

        #
        # IMPORTANT:
        #
        # Do not copy normal Termux/Bionic X11 libraries.
        #
        # Only bundle these if android/wayland-deps/usr/lib is known to contain
        # GLIBC builds.
        #

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
        # licenses
        #######################################################################

        #
        # Android ntsync license is intentionally NOT copied because this
        # glibc build does not build ntsync-android.
        #
        # Userspace ntsync.patch belongs to Wine itself.
        #

        #######################################################################
        # Strip
        #######################################################################

        echo
        echo "============================================================"
        echo " Stripping binaries"
        echo "============================================================"

        before_mb=$(du -sm "$OUTPUT_DIR" 2>/dev/null | cut -f1)

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

            "$STRIP" --strip-all "$f" 2>/dev/null ||
            "$STRIP" --strip-debug "$f" 2>/dev/null ||
            true

        done

        after_mb=$(du -sm "$OUTPUT_DIR" 2>/dev/null | cut -f1)

        echo "OUTPUT tree: ${before_mb}MB -> ${after_mb}MB"

        #######################################################################
        # Wine symlinks
        #######################################################################

        mkdir -p "$install_dir/bin"

        ln -sf \
            ../lib/wine/aarch64-unix/wine \
            "$install_dir/bin/wine"

        ln -sf \
            ../lib/wine/aarch64-unix/wine \
            "$OUTPUT_DIR/bin/wine"

        ln -sf \
            ../lib/wine/aarch64-unix/wine-preloader \
            "$OUTPUT_DIR/bin/wine-preloader"

        ln -sf \
            ../lib/wine/aarch64-unix/wine-preloader \
            "$install_dir/bin/wine-preloader"

        echo
        echo "Wine loader symlinks:"

        ls -la \
            "$OUTPUT_DIR/bin/wine" \
            "$OUTPUT_DIR/bin/wine-preloader"

        #######################################################################
        # Termux:X11 launcher
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
        # glibc environment
        #######################################################################

        cat > "$OUTPUT_DIR/glibc-env.sh" <<EOF
export TERMUX_PREFIX="$TERMUX_PREFIX"
export GLIBC_PREFIX="$GLIBC_PREFIX"
export WINE_PREFIX="$install_dir"

export DISPLAY="\${DISPLAY:-:0}"
export GDK_BACKEND=x11
export XDG_SESSION_TYPE=x11
export TERMUX_X11_FORCE_FLIP="\${TERMUX_X11_FORCE_FLIP:-1}"

export TMPDIR="$TERMUX_TMPDIR"
export TMP="\$TMPDIR"
export TEMP="\$TMPDIR"

export LD_LIBRARY_PATH="\$WINE_PREFIX/lib:\$GLIBC_PREFIX/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"

export PATH="\$WINE_PREFIX/bin:\$PATH"
EOF

        #######################################################################
        # Build information
        #######################################################################

        cat > "$OUTPUT_DIR/build-info.txt" <<EOF
Wine ARM64EC Proton 11.0-1
==========================

Unix ABI:
  AArch64 GNU/Linux glibc

Unix target:
  $TARGET

Windows architectures:
  arm64ec
  aarch64
  i386

Runtime:
  Termux glibc

Termux glibc:
  $GLIBC_PREFIX

Wine:
  $install_dir

Primary display:
  Termux:X11

DISPLAY:
  :0

Wayland:
  enabled / optional

Android/Bionic Wine Unix compiler:
  NO

Android NDK:
  NOT USED

LLVM-MinGW:
  $LLVM_MINGW_TOOLCHAIN
EOF

        #######################################################################
        # Final ELF check
        #######################################################################

        echo
        echo "============================================================"
        echo " Final ELF verification"
        echo "============================================================"

        if [ -e "$OUTPUT_DIR/lib/wine/aarch64-unix/wine" ]; then

            echo
            echo "Wine ELF:"
            file "$OUTPUT_DIR/lib/wine/aarch64-unix/wine" || true

            echo
            echo "Wine NEEDED:"
            readelf -d \
                "$OUTPUT_DIR/lib/wine/aarch64-unix/wine" \
                2>/dev/null |
                grep NEEDED ||
                true

            echo
            echo "Wine interpreter:"

            readelf -l \
                "$OUTPUT_DIR/lib/wine/aarch64-unix/wine" \
                2>/dev/null |
                grep "Requesting program interpreter" ||
                true

        fi

        #######################################################################
        # Final layer verification
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

        #
        # Native Wine
        #

        check_file "$OUTPUT_DIR/lib/wine/aarch64-unix/wine"

        #
        # X11
        #

        if find "$OUTPUT_DIR/lib/wine" \
            -type f \
            \( -name 'winex11.drv.so' -o -name 'winex11.drv' \) \
            2>/dev/null |
            grep -q .
        then
            echo "OK   winex11.drv"
        else
            echo "FAIL winex11.drv"
            fail=1
        fi

        #
        # Wayland
        #

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

        #
        # AGS
        #

        if ls "$OUTPUT_DIR"/lib/wine/*/amd_ags_x64.dll \
            >/dev/null 2>&1
        then
            echo "OK   amd_ags_x64.dll"
        else
            echo "FAIL amd_ags_x64.dll"
            fail=1
        fi

        if [ "$fail" != "0" ]; then

            echo
            echo "FATAL: layer verification failed."
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
        echo "Environment:"
        echo "  $OUTPUT_DIR/glibc-env.sh"

    fi

done
