# Dot-source to put the Doro Cam toolchain on PATH for the current PowerShell session:
#   . .\scripts\dev-env.ps1
# Tools are installed user-level under $env:DORO_DEV_HOME (default: $HOME\dev), so no admin rights are needed.
$dev = if ($env:DORO_DEV_HOME) { $env:DORO_DEV_HOME } else { Join-Path $HOME 'dev' }
$env:JAVA_HOME = Join-Path $dev 'jdk-17'
$env:ANDROID_HOME = Join-Path $dev 'android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$paths = @(
  (Join-Path $dev 'flutter\bin'),
  (Join-Path $env:JAVA_HOME 'bin'),
  (Join-Path $env:ANDROID_HOME 'cmdline-tools\latest\bin'),
  (Join-Path $env:ANDROID_HOME 'platform-tools'),
  (Join-Path $env:ANDROID_HOME 'emulator'),
  (Join-Path $env:APPDATA 'npm')
)
foreach ($p in $paths) { if (($env:Path -split ';') -notcontains $p) { $env:Path = "$p;$env:Path" } }
Write-Host "Doro Cam toolchain: JAVA_HOME=$env:JAVA_HOME ANDROID_HOME=$env:ANDROID_HOME"
