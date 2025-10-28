# MMORPG Migration Helper Script (PowerShell)
# Provides convenience commands for managing MMORPG database migrations

param(
    [Parameter(Position=0)]
    [string]$Command,

    [Parameter(Position=1)]
    [string]$Arg1,

    [Parameter(Position=2)]
    [string]$Arg2
)

$ErrorActionPreference = "Stop"

# Get script and project paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Show-Help {
    @"
MMORPG Migration Helper

Usage: .\mmorpg_migrate.ps1 <command> [options]

Commands:
    create <name>       Create new MMORPG migration with timestamp
    status              Show migration status
    up [limit]          Apply migrations (optional: limit count)
    down [limit]        Rollback migrations (optional: limit count)
    redo                Redo last migration
    test                Run migration test cycle (up/down/up)
    verify              Verify migration files are properly formatted

Examples:
    .\mmorpg_migrate.ps1 create accounts     # Creates 20250128HHMMSS_mmorpg_accounts.sql
    .\mmorpg_migrate.ps1 status              # Show applied/pending migrations
    .\mmorpg_migrate.ps1 up                  # Apply all pending migrations
    .\mmorpg_migrate.ps1 up 1                # Apply 1 migration
    .\mmorpg_migrate.ps1 down 1              # Rollback 1 migration

Environment Variables:
    DB_HOST      Database host (default: localhost)
    DB_PORT      Database port (default: 5432)
    DB_USER      Database user (default: nakama)
    DB_PASS      Database password (default: nakama)
    DB_NAME      Database name (default: nakama)
"@
}

function Get-Timestamp {
    Get-Date -Format "yyyyMMddHHmmss"
}

function New-Migration {
    param([string]$Name)

    if ([string]::IsNullOrEmpty($Name)) {
        Write-Error-Custom "Migration name required"
        Write-Host "Usage: .\mmorpg_migrate.ps1 create <name>"
        exit 1
    }

    $Timestamp = Get-Timestamp
    $Filename = "${Timestamp}_mmorpg_${Name}.sql"
    $Filepath = Join-Path $ProjectRoot "migrate\sql\$Filename"

    if (Test-Path $Filepath) {
        Write-Error-Custom "Migration file already exists: $Filename"
        exit 1
    }

    $Content = @"
/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - $($Name.Substring(0,1).ToUpper() + $Name.Substring(1)) Migration
 *
 * Description: TODO
 *
 * Requirements: TODO (list requirement numbers)
 * Design Reference: Data Models section
 * Task: TODO (e.g., 1.1.2)
 */

-- +migrate Up

-- TODO: Add schema changes here
CREATE TABLE IF NOT EXISTS mmorpg_${Name} (
    id UUID PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- +migrate Down

DROP TABLE IF EXISTS mmorpg_${Name};
"@

    $Content | Out-File -FilePath $Filepath -Encoding UTF8

    Write-Info "Created migration: $Filename"
    Write-Info "Edit file: $Filepath"
}

function Invoke-NakamaMigrate {
    param(
        [string]$Cmd,
        [string]$Limit
    )

    $DbHost = if ($env:DB_HOST) { $env:DB_HOST } else { "localhost" }
    $DbPort = if ($env:DB_PORT) { $env:DB_PORT } else { "5432" }
    $DbUser = if ($env:DB_USER) { $env:DB_USER } else { "nakama" }
    $DbPass = if ($env:DB_PASS) { $env:DB_PASS } else { "nakama" }
    $DbName = if ($env:DB_NAME) { $env:DB_NAME } else { "nakama" }

    $NakamaExe = Join-Path $ProjectRoot "nakama.exe"
    if (-not (Test-Path $NakamaExe)) {
        $NakamaExe = (Get-Command nakama -ErrorAction SilentlyContinue).Source
        if (-not $NakamaExe) {
            Write-Error-Custom "Nakama binary not found. Build it first or ensure it's in PATH."
            exit 1
        }
    }

    $Args = @("migrate", $Cmd)

    if (-not [string]::IsNullOrEmpty($Limit)) {
        $Args += @("--limit", $Limit)
    }

    $Args += @(
        "--database.address", "${DbUser}:${DbPass}@${DbHost}:${DbPort}/${DbName}"
    )

    Write-Info "Running: $NakamaExe $($Args -join ' ')"
    & $NakamaExe $Args
}

function Test-Migrations {
    $Errors = 0

    Write-Info "Verifying MMORPG migration files..."

    $MigrationFiles = Get-ChildItem -Path (Join-Path $ProjectRoot "migrate\sql") -Filter "20*_mmorpg_*.sql"

    foreach ($File in $MigrationFiles) {
        $Content = Get-Content $File.FullName -Raw

        # Check for +migrate Up directive
        if ($Content -notmatch "-- \+migrate Up") {
            Write-Error-Custom "$($File.Name): Missing '-- +migrate Up' directive"
            $Errors++
        }

        # Check for +migrate Down directive
        if ($Content -notmatch "-- \+migrate Down") {
            Write-Error-Custom "$($File.Name): Missing '-- +migrate Down' directive"
            $Errors++
        }

        # Check timestamp format
        if ($File.Name -notmatch "^\d{14}_mmorpg_.+\.sql$") {
            Write-Warn "$($File.Name): Filename doesn't match expected format (YYYYMMDDHHMMSS_mmorpg_*.sql)"
        }
    }

    if ($Errors -eq 0) {
        Write-Info "All MMORPG migrations verified successfully"
    } else {
        Write-Error-Custom "Found $Errors error(s) in migration files"
        exit 1
    }
}

function Test-MigrationCycle {
    Write-Info "Running migration test cycle..."

    Write-Warn "This will apply and rollback migrations. Ensure you're using a test database!"
    $Response = Read-Host "Continue? (y/N)"

    if ($Response -ne "y" -and $Response -ne "Y") {
        Write-Info "Test cancelled"
        exit 0
    }

    Write-Info "Step 1: Apply migrations"
    Invoke-NakamaMigrate -Cmd "up" -Limit "1"

    Write-Info "Step 2: Rollback migrations"
    Invoke-NakamaMigrate -Cmd "down" -Limit "1"

    Write-Info "Step 3: Reapply migrations"
    Invoke-NakamaMigrate -Cmd "up" -Limit "1"

    Write-Info "Migration test cycle completed successfully"
}

# Main command dispatcher
switch ($Command) {
    "create" {
        New-Migration -Name $Arg1
    }
    "status" {
        Invoke-NakamaMigrate -Cmd "status"
    }
    "up" {
        Invoke-NakamaMigrate -Cmd "up" -Limit $Arg1
    }
    "down" {
        Invoke-NakamaMigrate -Cmd "down" -Limit $Arg1
    }
    "redo" {
        Invoke-NakamaMigrate -Cmd "redo"
    }
    "verify" {
        Test-Migrations
    }
    "test" {
        Test-MigrationCycle
    }
    { $_ -in "help", "--help", "-h", "" } {
        Show-Help
    }
    default {
        Write-Error-Custom "Unknown command: $Command"
        Write-Host ""
        Show-Help
        exit 1
    }
}
