#!/bin/bash
# Fabrica FFmpeg y FFprobe para Android (arm64) SIN codificadores H.264/H.265 con patentes (no x264, no x265...).
# H.264 y H.265 se crean con el codificador del propio celular (MediaCodec). AV1 con SVT-AV1 (libre).
# Librerias incluidas: freetype, harfbuzz, fribidi, libass (subtitulos), zimg (zscale: HDR), vid.stab (estabilizador), SVT-AV1.
# Como lleva vid.stab (GPL), el resultado es GPL-3.0 (igual que el FFmpeg de la PC); el codigo fuente se publica junto con Godit.
# Se ejecuta en GitHub Actions (NDK incluido). Resultado: out/ffmpeg y out/ffprobe.
set -euo pipefail

FFMPEG_SHA="${FFMPEG_SHA:-d4070a14cecc7e29eb278f9b6036c2284255f70d}"
API=26
NDK="${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_HOME:?falta el NDK}}"
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
ARCH="${ARCH:-arm64}"        # arm64 (celulares) | x86_64 (celular simulado para las pruebas automaticas)
if [ "$ARCH" = "x86_64" ]; then
  HOST=x86_64-linux-android; FF_ARCH=x86_64; FF_CPU=x86-64; ABI=x86_64; EXTRA_FF="--disable-asm"; EXTRA_SVT="-DCOMPILE_C_ONLY=ON"
else
  HOST=aarch64-linux-android; FF_ARCH=aarch64; FF_CPU=armv8-a; ABI=arm64-v8a; EXTRA_FF="--enable-neon"; EXTRA_SVT=""
fi
ROOT="$PWD"
OUT="$ROOT/out"
PREFIX="$ROOT/deps"
SRC="$ROOT/src"
mkdir -p "$OUT" "$PREFIX" "$SRC"

export PATH="$TC/bin:$PATH"
export CC="$TC/bin/${HOST}${API}-clang"
export CXX="$TC/bin/${HOST}${API}-clang++"
export AR="$TC/bin/llvm-ar" RANLIB="$TC/bin/llvm-ranlib" STRIP="$TC/bin/llvm-strip" NM="$TC/bin/llvm-nm"
export CFLAGS="-O2 -fPIC -I$PREFIX/include" CXXFLAGS="-O2 -fPIC -I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
J="$(nproc)"

CMAKE_COMUN=(-G Ninja -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" -DANDROID_ABI=$ABI -DANDROID_PLATFORM=android-$API
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH="$PREFIX" -DBUILD_SHARED_LIBS=OFF
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5)

bajar() {   # bajar <url> <carpeta> : descarga y descomprime en src/<carpeta> (sin el primer nivel)
  local url="$1" dir="$2"
  [ -d "$SRC/$dir" ] && return 0
  mkdir -p "$SRC/$dir"
  curl -fsSL "$url" | tar -x --strip-components=1 -C "$SRC/$dir" $( [[ "$url" == *.xz ]] && echo -J || echo -z )
}
cmake_dep() {   # cmake_dep <carpeta> [opciones...]
  local d="$1"; shift
  cmake -S "$SRC/$d" -B "$SRC/$d/_b" "${CMAKE_COMUN[@]}" "$@"
  cmake --build "$SRC/$d/_b" -j"$J"
  cmake --install "$SRC/$d/_b"
}
auto_dep() {    # auto_dep <carpeta> [opciones...]
  local d="$1"; shift
  ( cd "$SRC/$d" && ./configure --host="$HOST" --prefix="$PREFIX" --enable-static --disable-shared --with-pic "$@" && make -j"$J" && make install )
}

# ---------------------------------------------------------------- librerias
# Android trae zlib en el sistema (-lz); las demas librerias la piden por pkg-config
mkdir -p "$PREFIX/lib/pkgconfig"
cat > "$PREFIX/lib/pkgconfig/zlib.pc" <<'EOF2'
Name: zlib
Description: zlib del sistema de Android
Version: 1.2.13
Libs: -lz
Cflags:
EOF2
echo "== freetype";  bajar https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.xz freetype
cmake_dep freetype -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_HARFBUZZ=ON

echo "== harfbuzz";  bajar https://github.com/harfbuzz/harfbuzz/releases/download/10.1.0/harfbuzz-10.1.0.tar.xz harfbuzz
cmake_dep harfbuzz -DHB_HAVE_FREETYPE=ON -DHB_BUILD_SUBSET=OFF -DHB_BUILD_UTILS=OFF

echo "== fribidi";   bajar https://github.com/fribidi/fribidi/releases/download/v1.0.16/fribidi-1.0.16.tar.xz fribidi
auto_dep fribidi --disable-docs --disable-bin --disable-debug

echo "== libass";    bajar https://github.com/libass/libass/releases/download/0.17.3/libass-0.17.3.tar.xz libass
auto_dep libass --disable-fontconfig --disable-asm --disable-require-system-font-provider --disable-libunibreak

echo "== zimg";      bajar https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.5.tar.gz zimg
( cd "$SRC/zimg" && ./autogen.sh )
auto_dep zimg --disable-simd

echo "== vid.stab";  bajar https://github.com/georgmartius/vid.stab/archive/refs/tags/v1.1.1.tar.gz vidstab
cmake_dep vidstab -DUSE_OMP=OFF -DBUILD_SHARED_LIBS=OFF

echo "== SVT-AV1";   bajar https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v3.0.0/SVT-AV1-v3.0.0.tar.gz svtav1
cmake_dep svtav1 $EXTRA_SVT -DBUILD_APPS=OFF -DBUILD_DEC=OFF -DBUILD_TESTING=OFF -DSVT_AV1_LTO=OFF

# ---------------------------------------------------------------- LibRaw (fotos RAW) + puente para Python
echo "== LibRaw";    bajar https://www.libraw.org/data/LibRaw-0.21.3.tar.gz libraw
( cd "$SRC/libraw" && ./configure --host="$HOST" --prefix="$PREFIX" --enable-static --disable-shared --with-pic --disable-openmp --disable-examples --disable-jpeg --disable-lcms --disable-zlib && make -j"$J" && make install )
"$CXX" -shared -fPIC -O2 -static-libstdc++ -o "$OUT/libgodit_raw.so" "$ROOT/tools/godit_raw.c" -I"$PREFIX/include" -L"$PREFIX/lib" -lraw -lm

# ---------------------------------------------------------------- whisper.cpp (subtitulos automaticos)
echo "== whisper.cpp"; bajar https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.7.5.tar.gz whisper
cmake -S "$SRC/whisper" -B "$SRC/whisper/_b" "${CMAKE_COMUN[@]}" -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_BUILD_SERVER=OFF   -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF -DWHISPER_SDL2=OFF -DANDROID_STL=c++_static
cmake --build "$SRC/whisper/_b" --target whisper-cli -j"$J"
cp "$SRC/whisper/_b/bin/whisper-cli" "$OUT/whisper-cli"
"$STRIP" "$OUT/whisper-cli"

# ---------------------------------------------------------------- FFmpeg
if [ ! -d "$SRC/ffmpeg/.git" ]; then
  mkdir -p "$SRC/ffmpeg" && cd "$SRC/ffmpeg"
  git init -q . && git remote add origin https://github.com/FFmpeg/FFmpeg.git
  git fetch -q --depth 1 origin "$FFMPEG_SHA" && git checkout -q FETCH_HEAD
  cd "$ROOT"
fi

cd "$SRC/ffmpeg"
./configure \
  --prefix="$OUT/prefix" \
  --enable-cross-compile --target-os=android --arch=$FF_ARCH --cpu=$FF_CPU $EXTRA_FF \
  --cc="$CC" --cxx="$CXX" --ar="$AR" --nm="$NM" --ranlib="$RANLIB" --strip="$STRIP" \
  --sysroot="$TC/sysroot" \
  --enable-pic --enable-jni --enable-mediacodec \
  --enable-gpl --enable-version3 \
  --pkg-config="pkg-config" --pkg-config-flags="--static" \
  --enable-zlib \
  --enable-libass --enable-libfreetype --enable-libharfbuzz --enable-libfribidi \
  --enable-libzimg --enable-libvidstab --enable-libsvtav1 \
  --enable-small --disable-doc --disable-ffplay --disable-debug \
  --disable-autodetect \
  --extra-cflags="-O2 -I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib" \
  --extra-ldexeflags="-pie -static-libstdc++" --extra-libs="-lm"
make -j"$J"
make install
"$STRIP" "$OUT/prefix/bin/ffmpeg" "$OUT/prefix/bin/ffprobe"
cp "$OUT/prefix/bin/ffmpeg" "$OUT/prefix/bin/ffprobe" "$OUT/"
test -f "$OUT/libgodit_raw.so" && test -f "$OUT/whisper-cli"
ls -la "$OUT"
