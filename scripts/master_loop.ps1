param (
    [int]$WaitMinutes = 30,
    [string]$AdbPort = "5555"
)

$ErrorActionPreference = "Stop"

# Constants
$AppPackage = "com.example.golden_p"
$AppActivity = ".MainActivity"
$AdbDevice = "127.0.0.1:$AdbPort"
$ApkPath = "build\app\outputs\flutter-apk\app-release.apk"
$adb = "C:\Users\Admin N\AppData\Local\Android\Sdk\platform-tools\adb.exe"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " V123: Autonomous 24/7 AI Optimization Loop" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# Step 1: Connect ADB
Write-Host "[1/5] Connecting to LDPlayer via ADB on $AdbDevice..." -ForegroundColor Yellow
& $adb connect $AdbDevice

# Initial Build and Install
Write-Host "Doing initial build and install..." -ForegroundColor Yellow
flutter build apk --release
if ($LASTEXITCODE -ne 0) { Write-Host "Build failed!" -ForegroundColor Red; exit }
& $adb -s $AdbDevice install -r $ApkPath
& $adb -s $AdbDevice shell am start -n "$AppPackage/$AppActivity"

$LoopCount = 1

while ($true) {
    Write-Host "`n>>> Starting Loop #$LoopCount" -ForegroundColor Green
    
    # Wait for Data Collection
    Write-Host "[1/5] Waiting $WaitMinutes minutes for bot to collect data..." -ForegroundColor Yellow
    Start-Sleep -Seconds ($WaitMinutes * 60)
    
    # Pull Data
    Write-Host "[2/5] Pulling training data via ADB..." -ForegroundColor Yellow
    if (!(Test-Path -Path "training_data")) { New-Item -ItemType Directory -Path "training_data" }
    & $adb -s $AdbDevice pull /storage/emulated/0/Download/golden_p_training_data/ ./training_data/
    
    # Train AI Model
    Write-Host "[3/5] Training ML Model and Generating Params..." -ForegroundColor Yellow
    python scripts/train_model.py
    
    # Apply Params (OTA Update)
    Write-Host "[4/4] Pushing optimized parameters to device via OTA..." -ForegroundColor Yellow
    & $adb -s $AdbDevice push optimized_params.json /storage/emulated/0/Android/data/com.example.golden_p/files/optimized_params.json
    
    Write-Host "OTA Update successful! Bot will use new brain on next round." -ForegroundColor Green
    $LoopCount++
}
