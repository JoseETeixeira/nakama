# Nakama Development Helper Script for Windows
# Usage: .\dev.ps1 <command>

param(
    [Parameter(Position=0)]
    [string]$Command = "help"
)

function Show-Help {
    Write-Host "Nakama MMORPG Development Commands:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  build-modules     " -ForegroundColor Green -NoNewline
    Write-Host "Compile TypeScript modules to JavaScript"
    Write-Host "  watch-modules     " -ForegroundColor Green -NoNewline
    Write-Host "Watch and auto-compile TypeScript modules"
    Write-Host "  up                " -ForegroundColor Green -NoNewline
    Write-Host "Build modules and start Docker Compose stack"
    Write-Host "  up-build          " -ForegroundColor Green -NoNewline
    Write-Host "Build modules and start with Docker image rebuild"
    Write-Host "  down              " -ForegroundColor Green -NoNewline
    Write-Host "Stop Docker Compose stack"
    Write-Host "  restart           " -ForegroundColor Green -NoNewline
    Write-Host "Rebuild modules and restart Nakama container"
    Write-Host "  logs              " -ForegroundColor Green -NoNewline
    Write-Host "Show Nakama logs"
    Write-Host "  clean             " -ForegroundColor Green -NoNewline
    Write-Host "Clean compiled JavaScript files"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\dev.ps1 up              # Build and start"
    Write-Host "  .\dev.ps1 watch-modules   # Watch for changes"
    Write-Host "  .\dev.ps1 restart         # Rebuild and restart"
}

function Build-Modules {
    Write-Host "Building TypeScript modules..." -ForegroundColor Cyan
    npm run build
}

function Watch-Modules {
    Write-Host "Watching TypeScript modules..." -ForegroundColor Cyan
    npm run watch
}

function Start-Stack {
    Build-Modules
    Write-Host "Starting Nakama stack..." -ForegroundColor Cyan
    docker compose up
}

function Start-StackBuild {
    Build-Modules
    Write-Host "Building and starting Nakama stack..." -ForegroundColor Cyan
    docker compose up --build
}

function Stop-Stack {
    docker compose down
}

function Restart-Nakama {
    Build-Modules
    Write-Host "Restarting Nakama..." -ForegroundColor Cyan
    docker compose restart nakama
}

function Show-Logs {
    docker compose logs -f nakama
}

function Clean-Modules {
    Write-Host "Cleaning compiled modules..." -ForegroundColor Cyan
    Get-ChildItem -Path "data\modules" -Filter "*.js" -Recurse | Remove-Item -Force
    Write-Host "Cleaned" -ForegroundColor Green
}

# Command routing
switch ($Command.ToLower()) {
    "help" { Show-Help }
    "build-modules" { Build-Modules }
    "watch-modules" { Watch-Modules }
    "up" { Start-Stack }
    "up-build" { Start-StackBuild }
    "down" { Stop-Stack }
    "restart" { Restart-Nakama }
    "logs" { Show-Logs }
    "clean" { Clean-Modules }
    default {
        Write-Host "Unknown command: $Command" -ForegroundColor Red
        Write-Host ""
        Show-Help
        exit 1
    }
}
