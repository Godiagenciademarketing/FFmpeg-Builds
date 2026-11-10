#!/bin/bash
# Compila SOLO LibRaw y el puente libgodit_raw.so (rapido). Se ejecuta siempre, aunque FFmpeg venga de la memoria cache.
set -euo pipefail
ARCH="${ARCH:-arm64}"
NDK="${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_HOME:?falta el NDK}}"
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
API=26
if [ "$ARCH" = "x86_64" ]; then HOST=x86_64-linux-android; else HOST=aarch64-linux-android; fi
ROOT="$PWD"; PREFIX="$ROOT/deps-raw"; mkdir -p "$PREFIX" out src-raw
export PATH="$TC/bin:$PATH"
export CC="$TC/bin/${HOST}${API}-clang" CXX="$TC/bin/${HOST}${API}-clang++" AR="$TC/bin/llvm-ar" RANLIB="$TC/bin/llvm-ranlib" STRIP="$TC/bin/llvm-strip"
export CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC"
[ -d src-raw/libraw ] || { mkdir -p src-raw/libraw; curl -fsSL https://www.libraw.org/data/LibRaw-0.21.3.tar.gz | tar xz --strip-components=1 -C src-raw/libraw; }
( cd src-raw/libraw && ./configure --host="$HOST" --prefix="$PREFIX" --enable-static --disable-shared --with-pic --disable-openmp --disable-examples --disable-jpeg --disable-lcms --disable-zlib && make -j"$(nproc)" && make install )
"$CXX" -shared -fPIC -O2 -static-libstdc++ -o out/libgodit_raw.so tools/godit_raw.c -I"$PREFIX/include" -L"$PREFIX/lib" -lraw -lm
"$TC/bin/llvm-nm" -D out/libgodit_raw.so | grep -E " T godit_raw_(leer|liberar)$"
ls -la out/libgodit_raw.so
