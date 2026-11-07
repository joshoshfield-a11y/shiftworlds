#!/bin/bash
# Shiftworlds APK build — direct SDK tools, no Gradle.
# Adapted from ~/workspace/voxbox-amberfall/apk/build.sh (same pipeline:
# javac → aapt2 compile/link → d8 dex → aapt add classes.dex →
# zipalign → apksigner sign (debug keystore) → verify + badging).
# Packages the current single-file shiftworlds.html from the Game Off 2026
# goal files, byte-verified against the packaged copy (cmp aborts the
# build on any difference).
# Identity: package com.dogbyte.shiftworlds, versionCode 1, versionName 1.0.
# Keystore: apk/debug.keystore, alias shiftworlds, DEBUG ONLY. A NEW
# per-game debug keystore (no shared cross-game debug keystore exists —
# Surface Wars, STARFALL, Scrap Dungeon, VoxBox each carry their own).
# Future Shiftworlds updates MUST reuse this keystore to install over v1.0.
# Release signing is a user-only step, NOT this script.
# Icon: generated from
# ~/workspace/game-icons/media-generation-shiftworlds-0-b410037d-d5d7-4fed-8c71-581f9acd685b.webp
# into res/mipmap-*/ic_launcher.png (+ ic_launcher_round.png) at all
# densities; icon-512.png at apk root is the Play Store listing asset.
# Run from ~/workspace/shiftworlds/apk.
set -euo pipefail
export _JAVA_OPTIONS="-Djava.net.preferIPv4Stack=true"
SDK=~/android-sdk
BT=$SDK/build-tools/35.0.0
PLATFORM=$SDK/platforms/android-35/android.jar
JAVA_HOME=~/jdk17
export PATH="$JAVA_HOME/bin:$PATH"
JAVAC=$JAVA_HOME/bin/javac
KEYTOOL=$JAVA_HOME/bin/keytool
MAGICK=~/tools/imagemagick7/bin/magick
ROOT=~/workspace/shiftworlds
APKDIR=$ROOT/apk
SRC_HTML=~/workspace/goals/game-off-2026-entry/files/shiftworlds.html
ICON_WEBP=~/workspace/game-icons/media-generation-shiftworlds-0-b410037d-d5d7-4fed-8c71-581f9acd685b.webp
VERSION_CODE=${VERSION_CODE:-1}
VERSION_NAME=${VERSION_NAME:-1.0}
APK_NAME=${APK_NAME:-Shiftworlds_v1.0.apk}
OUT=$APKDIR/out
rm -rf "$OUT" "$APKDIR/assets"
mkdir -p "$OUT" "$APKDIR/assets/game"

# --- 0. Launcher icons from the WebP (regenerated every build) ---
for spec in "mdpi 48" "hdpi 72" "xhdpi 96" "xxhdpi 144" "xxxhdpi 192"; do
  set -- $spec; d=$1; s=$2
  "$MAGICK" "$ICON_WEBP" -resize "${s}x${s}" "$APKDIR/res/mipmap-$d/ic_launcher.png"
  # Round icon: same art, circular alpha mask.
  "$MAGICK" "$ICON_WEBP" -resize "${s}x${s}" \
    \( -size "${s}x${s}" xc:none -fill white -draw "circle $((s/2)),$((s/2)) 0,$((s/2))" \) \
    -alpha off -compose CopyOpacity -composite "$APKDIR/res/mipmap-$d/ic_launcher_round.png"
done
"$MAGICK" "$ICON_WEBP" -resize 512x512 "$APKDIR/icon-512.png"
echo "icons: $(for f in "$APKDIR"/res/mipmap-*/ic_launcher*.png; do "$MAGICK" identify -format "%f %wx%h\n" "$f"; done | tr '\n' '; ')"

# --- 1. Snapshot the current game HTML (single-file, no other assets) ---
cp "$SRC_HTML" "$APKDIR/assets/game/shiftworlds.html"
cmp "$SRC_HTML" "$APKDIR/assets/game/shiftworlds.html"
echo "shiftworlds.html bytes: $(stat -c%s "$APKDIR/assets/game/shiftworlds.html")"

# --- 2. Compile, link, dex, package ---
mkdir -p "$OUT/classes" "$OUT/gen"
"$JAVAC" -source 8 -target 8 -bootclasspath "$PLATFORM" \
  -d "$OUT/classes" "$APKDIR/src/com/dogbyte/shiftworlds/MainActivity.java"
"$BT/aapt2" compile --dir "$APKDIR/res" -o "$OUT/res.zip"
"$BT/aapt2" link -o "$OUT/unsigned.apk" -I "$PLATFORM" \
  --manifest "$APKDIR/AndroidManifest.xml" "$OUT/res.zip" \
  -A "$APKDIR/assets" --auto-add-overlay --java "$OUT/gen" \
  --min-sdk-version 28 --target-sdk-version 35 \
  --version-code "$VERSION_CODE" --version-name "$VERSION_NAME"
"$BT/d8" --lib "$PLATFORM" --output "$OUT" "$OUT/classes/com/dogbyte/shiftworlds/MainActivity.class"
cp "$OUT/unsigned.apk" "$OUT/packaged.apk"
# Add dex by relative name from inside $OUT: aapt stores the path as given,
# and an absolute path would land in the APK as /home/.../classes.dex (unloadable).
(cd "$OUT" && "$BT/aapt" add packaged.apk classes.dex >/dev/null)

# --- 3. Align + sign (Shiftworlds debug keystore, created once, reused after) ---
if [ ! -f "$APKDIR/debug.keystore" ]; then
  "$KEYTOOL" -genkeypair -v -keystore "$APKDIR/debug.keystore" -storepass android \
    -keypass android -alias shiftworlds -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Shiftworlds Debug, OU=Debug, O=Skit, C=US" >/dev/null
fi
"$BT/zipalign" -f 4 "$OUT/packaged.apk" "$OUT/aligned.apk"
"$BT/apksigner" sign --ks "$APKDIR/debug.keystore" --ks-pass pass:android \
  --key-pass pass:android --out "$OUT/$APK_NAME" "$OUT/aligned.apk"
"$BT/apksigner" verify "$OUT/$APK_NAME"
"$BT/zipalign" -c 4 "$OUT/$APK_NAME"
"$BT/aapt2" dump badging "$OUT/$APK_NAME"
cp "$OUT/$APK_NAME" ~/workspace/your_files/"$APK_NAME"
echo "APK: $(stat -c%s ~/workspace/your_files/"$APK_NAME") bytes"
sha256sum ~/workspace/your_files/"$APK_NAME"
