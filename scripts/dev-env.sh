# Source in Git Bash to put the Doro Cam toolchain on PATH:  source scripts/dev-env.sh
# Tools are installed user-level under $DORO_DEV_HOME (default: $HOME/dev), so no admin rights are needed.
DORO_DEV_HOME="${DORO_DEV_HOME:-$HOME/dev}"
# Gradle and the Android tools are Windows programs: give them Windows-style paths when cygpath exists.
to_native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
export JAVA_HOME="$(to_native "$DORO_DEV_HOME/jdk-17")"
export ANDROID_HOME="$(to_native "$DORO_DEV_HOME/android-sdk")"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$DORO_DEV_HOME/flutter/bin:$DORO_DEV_HOME/jdk-17/bin:$DORO_DEV_HOME/android-sdk/cmdline-tools/latest/bin:$DORO_DEV_HOME/android-sdk/platform-tools:$DORO_DEV_HOME/android-sdk/emulator:${APPDATA:+$(cygpath -u "$APPDATA")/npm:}$PATH"
echo "Doro Cam toolchain: JAVA_HOME=$JAVA_HOME ANDROID_HOME=$ANDROID_HOME"
