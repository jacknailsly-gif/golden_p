# Start LDPlayer 14 Instance 0 and Auto-launch Golden_p Bot

$ldPlayerExe = 'C:\LDPlayer\LDPlayer14\dnplayer.exe'
$ldPlayerDir = 'C:\LDPlayer\LDPlayer14'
$ldPlayerAdb = 'C:\LDPlayer\LDPlayer14\adb.exe'
$ldConsole   = 'C:\LDPlayer\LDPlayer14\ldconsole.exe'
$mainActivity = 'com.example.golden_p/.MainActivity'

Write-Host '[1/4] Launching LDPlayer 14 Instance 0 onto Desktop...' -ForegroundColor Cyan
Start-Process -FilePath $ldPlayerExe -ArgumentList 'index=0' -WorkingDirectory $ldPlayerDir

Write-Host '[2/4] Waiting for Android OS to boot...' -ForegroundColor Yellow
$booted = $false
for ($i = 1; $i -le 20; $i++) {
    Start-Sleep -Seconds 2
    $list = & $ldConsole list2
    if ($list -match '0,LDPlayer,\d+,\d+,2') {
        Write-Host "Emulator is booting (Step $i)..." -ForegroundColor Gray
    }
    # Check ADB
    & $ldPlayerAdb connect 127.0.0.1:5555 2>$null
    $devices = & $ldPlayerAdb devices
    if ($devices -match '127.0.0.1:5555\s+device') {
        $booted = $true
        Write-Host "✅ Android OS booted and ADB connected successfully!" -ForegroundColor Green
        break
    }
}

if (-not $booted) {
    Write-Host "Waiting extra 10s for final boot..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    & $ldPlayerAdb connect 127.0.0.1:5555 2>$null
}

Write-Host '[3/4] Starting Golden_p App on screen...' -ForegroundColor Cyan
& $ldPlayerAdb -s 127.0.0.1:5555 shell am start -n $mainActivity

Write-Host '🎉 [4/4] Done! Golden_p is now running on your LDPlayer screen.' -ForegroundColor Green
