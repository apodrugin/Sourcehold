#!/bin/sh
# This script is based on https://github.com/kewlbear/FFmpeg-iOS-build-script


# Functions

usage() {
    echo "usage: $(basename $0) [-adrv]"
    echo "options:"
    echo "-a        \tArchitectures to build. You may pass multiple architectures. Default value is 'arm64 armv7 i386 x86_64'"
    echo "-d        \tiOS deployment target. Default is '9.0'"
    echo "-r        \tPath to result directory. Default value is '.'."
    echo "-v        \tFFmpeg lib version to compile. Default value is '4.3.1'"
    exit 1
}

install_tools() {
    if [ ! `which yasm` ] ; then
        echo "Installing yasm..."
        brew install yasm || exit 1
    fi
    
    if [ ! `which gas-preprocessor.pl` ] ; then
        echo "Installing gas-preprocessor.pl..."
        (curl -L https://github.com/libav/gas-preprocessor/raw/master/gas-preprocessor.pl \
                -o /usr/local/bin/gas-preprocessor.pl \
                && chmod +x /usr/local/bin/gas-preprocessor.pl) \
                || exit 1
    fi
}

fetch_source() {
    local SOURCE="$1"
    local RESULT_DIR="$2"
    local SRC_DIR="$RESULT_DIR/$SOURCE"
    
    if [ ! -d "$SRC_DIR" ] ; then
        echo 'FFmpeg source not found. Fetching $SOURCE...'
        curl "http://www.ffmpeg.org/releases/$SOURCE.tar.bz2" | tar xj --directory "$RESULT_DIR" \
            || exit 1
    else
        echo "FFmpeg library source directory already exists."
    fi
}

compile() {
    echo "Compiling..."
    local ARCHS="$1"
    local DEPLOYMENT_TARGET="$2"
    local SRC_DIR="$3"
    local BUILD_DIR="$4"
    local LIB_DIR="$5"
    
    for ARCH in $ARCHS
    do
        echo "Building $ARCH..."
        mkdir -p "$BUILD_DIR/$ARCH"
        pushd "$BUILD_DIR/$ARCH" > /dev/null

        local CFLAGS="-arch $ARCH"
        local PLATFORM=
        local EXPORT=
        
        if [ "$ARCH" = "i386" -o "$ARCH" = "x86_64" ] ; then
            PLATFORM="iPhoneSimulator"
            CFLAGS="$CFLAGS -mios-simulator-version-min=$DEPLOYMENT_TARGET"
        else
            PLATFORM="iPhoneOS"
            CFLAGS="$CFLAGS -mios-version-min=$DEPLOYMENT_TARGET -fembed-bitcode"
            if [ "$ARCH" = "arm64" ] ; then
                EXPORT="GASPP_FIX_XCODE5=1"
            fi
        fi

        local XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
        local CC="xcrun -sdk $XCRUN_SDK clang"

        # force "configure" to use "gas-preprocessor.pl" (FFmpeg 3.3)
        if [ "$ARCH" = "arm64" ] ; then
            AS="gas-preprocessor.pl -arch aarch64 -- $CC"
        else
            AS="gas-preprocessor.pl -- $CC"
        fi

        CXXFLAGS="$CFLAGS"
        LDFLAGS="$CFLAGS"
        CONFIGURE_FLAGS="--enable-cross-compile --disable-debug --disable-programs --disable-doc --enable-pic"

        TMPDIR=${TMPDIR/%\/} "$SRC_DIR/configure" \
            --target-os=darwin \
            --arch=$ARCH \
            --cc="$CC" \
            --as="$AS" \
            $CONFIGURE_FLAGS \
            --extra-cflags="$CFLAGS" \
            --extra-ldflags="$LDFLAGS" \
            --prefix="$LIB_DIR/$ARCH" \
        || exit 1

        make -j3 install $EXPORT || exit 1
        
        popd > /dev/null
    done
}

create_fat_binaries() {
    echo "Building fat binaries..."
    local ARCHS="$1"
    local INCLUDE_DIR="$2"
    local LIB_DIR="$3"
    
    mkdir -p "$LIB_DIR"
    set - $ARCHS
    
    pushd "$LIB_DIR/$1/lib" > /dev/null
    
    for LIB in *.a
    do
        echo lipo -create `find $LIB_DIR -name $LIB` -output "$LIB_DIR/$LIB" 1>&2
        lipo -create `find $LIB_DIR -name $LIB` -output "$LIB_DIR/$LIB" || exit 1
    done

    popd > /dev/null
    
    cp -rf "$LIB_DIR/$1/include" "$INCLUDE_DIR"
}

cleanup() {
    echo "Cleaning up..."
    local ARCHS="$1"
    local BUILD_DIR="$2"
    local LIB_DIR="$3"
    
    rm -rf "$BUILD_DIR"
    
    for ARCH in $ARCHS
    do
        rm -rf "$LIB_DIR/$ARCH"
    done
}


#Script body

ARCHS="arm64 armv7 x86_64 i386"
DEPLOYMENT_TARGET="9.0"
FF_VERSION="4.3.1"
RESULT_DIR="."

while getopts "a:d:r:v:" opt
do
    case $opt in
    a)
        ARCHS="$OPTARG"
        ;;
    d)
        DEPLOYMENT_TARGET="$OPTARG"
        ;;
    r)
        RESULT_DIR="$OPTARG"
        ;;
    v)
        FF_VERSION="$OPTARG"
        ;;
    ?)
        usage
        ;;
    esac
done

mkdir -p "$RESULT_DIR"
# RESULT_DIR should be converted to absolute path to make 'compile' function work properly
RESULT_DIR=`cd "$RESULT_DIR"; pwd`

SOURCE="ffmpeg-$FF_VERSION"
SRC_DIR="$RESULT_DIR/$SOURCE"
BUILD_DIR="$RESULT_DIR/build"
INCLUDE_DIR="$RESULT_DIR/include"
LIB_DIR="$RESULT_DIR/lib"

install_tools
fetch_source "$SOURCE" "$RESULT_DIR"
compile "$ARCHS" "$DEPLOYMENT_TARGET" "$SRC_DIR" "$BUILD_DIR" "$LIB_DIR"
create_fat_binaries "$ARCHS" "$INCLUDE_DIR" "$LIB_DIR"
cleanup "$ARCHS" "$BUILD_DIR" "$LIB_DIR"

echo "Done"
