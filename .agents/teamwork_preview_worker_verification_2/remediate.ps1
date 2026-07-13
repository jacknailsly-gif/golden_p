# Remediation script to clean up files and verify build/tests

Write-Host "Starting remediation cleanup..."

$pathsToDelete = @(
    "test/white_prediction_test.dart",
    "golden_p"
)

foreach ($path in $pathsToDelete) {
    if (Test-Path $path) {
        Write-Host "Deleting $path..."
        Remove-Item -Path $path -Recurse -Force
    } else {
        Write-Host "$path does not exist."
    }
}

# Delete the corrupt legacy directory with special name
# Using exact string to avoid globbing issues
$corruptPath = 'test/main_test.dart      # Add a hello world test for your app'
if (Test-Path $corruptPath) {
    Write-Host "Deleting corrupt legacy path..."
    Remove-Item -LiteralPath $corruptPath -Recurse -Force
} else {
    Write-Host "Corrupt legacy path does not exist."
}

Write-Host "Running flutter analyze..."
flutter analyze

Write-Host "Running flutter test..."
flutter test
