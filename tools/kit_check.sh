#!/usr/bin/env bash
# RowCoachKit auf der Spark prüfen: Tests unter Linux, dann Bau (inkl. Tests) für Android arm64.
# Voraussetzungen (einmalig): Swift über swiftly (~/.local/share/swiftly), Swift SDK für Android
# (`swift sdk install …android.artifactbundle.tar.gz`), Android NDK ≥ r27 unter ~/Android/android-ndk-*
# und `setup-android-sdk.sh` aus dem SDK mit ANDROID_NDK_HOME ausgeführt. Siehe docs/ANDROID.md.
set -euo pipefail
export PATH="$HOME/.local/share/swiftly/bin:$PATH"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$(ls -d "$HOME"/Android/android-ndk-* | sort | tail -1)}"
cd "$(dirname "$0")/../App/RowCoachKit"
echo "== Linux: swift test"
swift test 2>&1 | grep -E "error|failed|Executed .* tests" | tail -3
echo "== Android arm64: Bibliothek und Tests bauen"
SDK=$(swift sdk list | grep -m1 android)
# Das neue Build-System ruft auf arm64-Linux den x86-Linker des NDK auf; das alte nutzt lld aus Swift
swift build --swift-sdk "aarch64-unknown-linux-android28" --build-system native --build-tests 2>&1 \
  | grep -vE "deprecated" | tail -2
echo "SDK: $SDK"
