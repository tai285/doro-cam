# Source inside WSL (Ubuntu) to put the Doro Cam toolchain on PATH:  source scripts/dev-env.sh
# All tests run in WSL (owner decision, see CLAUDE.md). Tools live under $DORO_DEV_HOME (default: $HOME/dev).
DORO_DEV_HOME="${DORO_DEV_HOME:-$HOME/dev}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
export ANDROID_HOME="$DORO_DEV_HOME/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$DORO_DEV_HOME/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
echo "Doro Cam toolchain: JAVA_HOME=$JAVA_HOME ANDROID_HOME=$ANDROID_HOME"
