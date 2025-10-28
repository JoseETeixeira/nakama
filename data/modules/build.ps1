# Automatically compile TypeScript modules to JavaScript
# This script runs before Nakama starts to ensure all TypeScript modules are compiled

Write-Host "Building TypeScript runtime modules..." -ForegroundColor Cyan

# Find all TypeScript files in subdirectories and compile them
Get-ChildItem -Path "data\modules" -Filter "*.ts" -Recurse | ForEach-Object {
    $tsFile = $_.FullName
    $dir = $_.DirectoryName
    $filename = $_.BaseName

    Write-Host "Compiling: $tsFile" -ForegroundColor Yellow

    # Compile TypeScript to JavaScript
    npx tsc "$tsFile" --target ES2015 --module commonjs --skipLibCheck

    # Copy the compiled JS file to the modules root directory
    $jsFile = Join-Path $dir "$filename.js"
    if (Test-Path $jsFile) {
        Copy-Item $jsFile -Destination "data\modules\$filename.js" -Force
        Write-Host "Copied $filename.js to modules root" -ForegroundColor Green
    }
}

Write-Host "TypeScript compilation complete!" -ForegroundColor Green
