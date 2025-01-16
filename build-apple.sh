#!/bin/sh

if [ -z "$1" ]; then
    echo "Usage: $0 <CURL Version>"
    exit 1
fi

OPENSSL_VERSION="openssl-3.4.0"

VERSION=$1
shift
BUILD_ARGS="$@"
BUILD_ARGS="--disable-shared --enable-static --with-secure-transport --with-openssl --without-libpsl --without-libidn2 --without-nghttp2 ${BUILD_ARGS}"

cd "$(dirname "$0")" || exit
ROOT="$(pwd -P)"

BUILDDIR="$ROOT/build"

#rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"
cd "$BUILDDIR" || exit

build_libssl() {
    SDK=$1
    ARCH=$2
    MIN=$3

    SOURCE="$BUILDDIR/openssl"
    LOG="$BUILDDIR/libssl-$SDK-$ARCH.log"

    if [ ! -d "$SOURCE" ]; then
        echo "- Check out OpenSSL $OPENSSL_VERSION"

        git clone --recursive --shallow-submodules --depth 1 --branch "$OPENSSL_VERSION" https://github.com/openssl/openssl.git >> "$LOG" 2>&1
    fi

    echo "- Build OpenSSL for $ARCH ($SDK)"

    cd "$SOURCE" || exit

    make distclean >> "$LOG" 2>&1

    if [ "$SDK" = "iphoneos" ]; then
        if [ "$ARCH" = "arm64" ]; then
            PLATFORM_FLAGS="no-async zlib-dynamic enable-ec_nistp_64_gcc_128"
            CONFIG="ios64-xcrun"
        elif [ "$ARCH" = "armv7" ]; then
            PLATFORM_FLAGS="no-async zlib-dynamic"
            CONFIG="ios-xcrun"
        else
            echo "OpenSSL configuration error: $ARCH on $SDK not supported!"
        fi
    elif [ "$SDK" = "iphonesimulator" ]; then
        if [ "$ARCH" = "arm64" ]; then
            PLATFORM_FLAGS="no-async zlib-dynamic enable-ec_nistp_64_gcc_128"
            CONFIG="iossimulator-xcrun"
        elif [ "$ARCH" = "i386" ]; then
            PLATFORM_FLAGS="no-asm"
            CONFIG="iossimulator-xcrun"
        elif [ "$ARCH" = "x86_64" ]; then
            PLATFORM_FLAGS="no-asm enable-ec_nistp_64_gcc_128"
            CONFIG="iossimulator-xcrun"
        else
            echo "OpenSSL configuration error: $ARCH on $SDK not supported!"
        fi
    elif [ "$SDK" = "macosx" ]; then
        if [ "$ARCH" = "i386" ]; then
            PLATFORM_FLAGS="no-asm"
            CONFIG="darwin-i386-cc"
        elif [ "$ARCH" = "x86_64" ]; then
            PLATFORM_FLAGS="no-asm enable-ec_nistp_64_gcc_128"
            CONFIG="darwin64-x86_64-cc"
        elif [ "$ARCH" = "arm64" ]; then
            PLATFORM_FLAGS="no-asm enable-ec_nistp_64_gcc_128"
            CONFIG="darwin64-arm64-cc"
        else
            echo "OpenSSL configuration error: $ARCH on $SDK not supported!"
        fi
    fi

    if [ -n "$CONFIG" ]; then
        ./Configure \
            no-shared \
            ${PLATFORM_FLAGS} \
            --prefix="$BUILDDIR/$SDK/libssl-$ARCH" \
            ${CONFIG} \
            CC="$(xcrun --sdk $SDK --find clang) -isysroot $(xcrun --sdk $SDK --show-sdk-path) -arch ${ARCH} -m$SDK-version-min=$MIN -fembed-bitcode" \
            >> "$LOG" 2>&1

        make depend >> "$LOG" 2>&1
        make "-j$(sysctl -n hw.logicalcpu_max)" build_libs >> "$LOG" 2>&1
        make install_dev >> "$LOG" 2>&1
    fi
}

build_libcurl() {
    SDK=$1
    ARCH=$2
    MIN=$3

    SOURCE="$BUILDDIR/libcurl"
    LOG="$BUILDDIR/libcurl-$SDK-$ARCH.log"

    ARCHIVE="$BUILDDIR/curl-$VERSION.tar.gz"
    if [ ! -f "$ARCHIVE" ]; then
        echo "- Download libcurl $VERSION"
        curl "https://curl.se/download/curl-$VERSION.tar.gz" > "$ARCHIVE"
    fi

    if [ -n "$GPG_VERIFY" ]; then
        echo "- Verify signature for curl-$VERSION.tar.gz"
        rm -f "$ARCHIVE.asc"
        curl "https://curl.se/download/curl-$VERSION.tar.gz.asc" > "$ARCHIVE.asc"
        gpg --verify "$ARCHIVE.asc" "$ARCHIVE" >/dev/null || exit
    fi

    echo "- Build libcurl for $ARCH ($SDK)"

    # curl build writes compiled files into source dir, so clean up, by removing and unpacking again.
    rm -rf "$SOURCE"
    mkdir -p "$SOURCE"

    tar -xzf "$ARCHIVE" -C "$SOURCE" --strip-components 1

    cd "$SOURCE" || exit

    for FILE in $(find "$ROOT/patches" -name '*.patch' 2>/dev/null); do
        patch -p1 < "$FILE"
    done

    SDKDIR=$(xcrun --sdk "$SDK" --show-sdk-path)

    echo "configure parameters: $BUILD_ARGS" >> "$LOG"

    HOST="$ARCH"

    if [ "$ARCH" = "arm64" ]; then
      HOST="arm"
    fi

    ./configure \
        --host="$HOST-apple-darwin" \
        $BUILD_ARGS \
        --prefix "$BUILDDIR/$SDK/libcurl-$ARCH" \
        CC="$(xcrun -find -sdk $SDK gcc)" \
        CFLAGS="-arch $ARCH -pipe -Os -gdwarf-2 -isysroot $SDKDIR -m$SDK-version-min=$MIN" \
        CPPFLAGS="-I$BUILDDIR/$SDK/libssl-$ARCH/include" \
        LDFLAGS="-arch $ARCH -isysroot $SDKDIR -L$BUILDDIR/$SDK/libssl-$ARCH/lib" \
        >> "$LOG" 2>&1

    make "-j$(sysctl -n hw.logicalcpu_max)" >> "$LOG" 2>&1
    make install >> "${LOG}" 2>&1
}

fatten() {
    SDK=$1
    NAME=$2
    LIB=${3:-$NAME}

    echo "- Fatten $LIB in $NAME ($SDK)"

    mkdir -p "$BUILDDIR/$SDK/$NAME/lib"

    lipo \
        -arch arm64 "$BUILDDIR/$SDK/$NAME-arm64/lib/$LIB.a" \
        -arch x86_64 "$BUILDDIR/$SDK/$NAME-x86_64/lib/$LIB.a" \
        -create -output "$BUILDDIR/$SDK/$NAME/lib/$LIB.a"
}

create_framework() {
    SDK=$1
    IS_FAT=$2

    mkdir -p "$BUILDDIR/$SDK/curl.framework/Headers"

    if [ -z "$IS_FAT" ]; then
        echo "- Create framework for $SDK"

        POSTFIX="-arm64"
    else
        echo "Create framework for fat $SDK"

        POSTFIX=""
      fi

    LIBS=("$BUILDDIR/$SDK/libssl$POSTFIX/lib/libssl.a" \
        "$BUILDDIR/$SDK/libssl$POSTFIX/lib/libcrypto.a" \
        "$BUILDDIR/$SDK/libcurl$POSTFIX/lib/libcurl.a")

    libtool -no_warning_for_no_symbols -static -o "$BUILDDIR/$SDK/curl.framework/curl" "${LIBS[@]}"

    HEADERS=("$BUILDDIR/$SDK/libssl-arm64/include"/* \
        "$BUILDDIR/$SDK/libcurl-arm64/include"/*)

    cp -r "${HEADERS[@]}" "$BUILDDIR/$SDK/curl.framework/Headers"
}


build_libssl      iphoneos          arm64   12.0
build_libcurl     iphoneos          arm64   12.0
create_framework  iphoneos

build_libssl      iphonesimulator   arm64   12.0
build_libssl      iphonesimulator   x86_64  12.0
fatten            iphonesimulator   libssl
fatten            iphonesimulator   libssl  libcrypto
build_libcurl     iphonesimulator   arm64   12.0
build_libcurl     iphonesimulator   x86_64  12.0
fatten            iphonesimulator   libcurl
create_framework  iphonesimulator   fat

build_libssl      macosx            arm64   10.13
build_libssl      macosx            x86_64  10.13
fatten            macosx            libssl
fatten            macosx            libssl  libcrypto
build_libcurl     macosx            arm64   10.13
build_libcurl     macosx            x86_64  10.13
fatten            macosx            libcurl
create_framework  macosx            fat

rm -rf curl.xcframework
xcodebuild -create-xcframework \
    -framework "$BUILDDIR/iphoneos/curl.framework" \
    -framework "$BUILDDIR/iphonesimulator/curl.framework" \
    -framework "$BUILDDIR/macosx/curl.framework" \
    -output "$ROOT/curl.xcframework"

plutil -insert CFBundleVersion -string "$VERSION" "$ROOT/curl.xcframework/Info.plist"
