param(
    [string]$Device = 'emulator-5554'
)

$ErrorActionPreference = 'Stop'
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$flutter = 'C:\Users\Marco\flutter\bin\flutter.bat'
$package = 'com.example.speedometer'

function Install-TestApp {
    & $flutter build apk --debug
    & $adb -s $Device install -r 'build\app\outputs\flutter-apk\app-debug.apk'
}

function Run-Scenario([string]$testPath) {
    & $flutter test $testPath -d $Device --timeout 90s --no-uninstall
    if ($LASTEXITCODE -ne 0) {
        throw "O cenário $testPath falhou com código $LASTEXITCODE."
    }
}

Install-TestApp
Run-Scenario 'integration_test\voice_band_interval_test.dart'
Run-Scenario 'integration_test\custom_speed_limit_test.dart'
& $adb -s $Device shell pm revoke $package android.permission.ACCESS_FINE_LOCATION
& $adb -s $Device shell pm revoke $package android.permission.ACCESS_COARSE_LOCATION
& $adb -s $Device shell pm set-permission-flags $package android.permission.ACCESS_FINE_LOCATION user-set
& $adb -s $Device shell pm set-permission-flags $package android.permission.ACCESS_FINE_LOCATION user-fixed
& $adb -s $Device shell pm set-permission-flags $package android.permission.ACCESS_COARSE_LOCATION user-set
& $adb -s $Device shell pm set-permission-flags $package android.permission.ACCESS_COARSE_LOCATION user-fixed
Run-Scenario 'integration_test\permission_denied_test.dart'

try {
    Install-TestApp
    & $adb -s $Device shell pm grant $package android.permission.ACCESS_FINE_LOCATION
    & $adb -s $Device shell pm grant $package android.permission.ACCESS_COARSE_LOCATION
    & $adb -s $Device shell settings put secure location_mode 0
    Run-Scenario 'integration_test\location_disabled_test.dart'
}
finally {
    & $adb -s $Device shell settings put secure location_mode 3
}
