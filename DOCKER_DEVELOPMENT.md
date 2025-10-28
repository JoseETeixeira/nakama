# Docker Compose Development Workflow

This document describes the automated development workflow for working with Nakama's TypeScript runtime modules using Docker Compose.

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Node.js (v16+)
- npm

### Setup

```powershell
# Install Node.js dependencies
npm install

# Build TypeScript modules
npm run build

# Start the stack
docker compose up
```

Or use the automated helper:

```powershell
# Windows PowerShell
.\dev.ps1 up

# Linux/Mac
make up
```

## Automated TypeScript Compilation

The project now includes an automated build system that compiles TypeScript runtime modules before starting Docker Compose.

### Available Commands

#### Windows (PowerShell)

```powershell
.\dev.ps1 help              # Show all commands
.\dev.ps1 build-modules     # Compile TypeScript modules
.\dev.ps1 up                # Build + start stack
.\dev.ps1 up-build          # Build + start with image rebuild
.\dev.ps1 restart           # Rebuild modules + restart Nakama
.\dev.ps1 watch-modules     # Auto-compile on file changes
.\dev.ps1 logs              # View Nakama logs
.\dev.ps1 clean             # Remove compiled files
```

#### Linux/Mac (Makefile)

```bash
make help              # Show all commands
make build-modules     # Compile TypeScript modules
make up                # Build + start stack
make up-build          # Build + start with image rebuild
make restart           # Rebuild modules + restart Nakama
make watch-modules     # Auto-compile on file changes
make logs              # View Nakama logs
make clean             # Remove compiled files
```

#### npm Scripts

```bash
npm run build          # Compile TypeScript modules once
npm run watch          # Watch and auto-compile
npm run dev            # Build + start (docker compose up)
npm run dev:build      # Build + start with image rebuild
```

## Development Workflow

### Option 1: Watch Mode (Recommended)

Run watch mode in one terminal to auto-compile TypeScript on save:

```powershell
# Terminal 1: Auto-compile
npm run watch
# or
.\dev.ps1 watch-modules

# Terminal 2: Docker Compose
docker compose up
```

When you modify TypeScript files, they'll auto-compile. Then restart Nakama:

```powershell
docker compose restart nakama
```

### Option 2: Manual Rebuild

```powershell
# 1. Modify TypeScript files
# 2. Build and restart
.\dev.ps1 restart
```

### Option 3: One Command Startup

```powershell
# Automatically builds TypeScript then starts Docker
.\dev.ps1 up
```

## TypeScript Module Structure

```
data/modules/
├── character/
│   ├── character.ts       # TypeScript source (tracked in git)
│   ├── character.js       # Compiled output (gitignored)
│   └── README.md
├── character.js           # Copied to root for Nakama (gitignored)
├── build.sh               # Bash build script
├── build.ps1              # PowerShell build script
└── README.md              # TypeScript build documentation
```

**Key Points:**
- Write TypeScript in subdirectories (`data/modules/character/character.ts`)
- Build system compiles `.ts` → `.js` in the same directory
- Build system copies `.js` files to `data/modules/` root
- Nakama loads from `data/modules/` root via volume mount

## Docker Configuration

The `docker-compose.yml` includes:

```yaml
volumes:
  - ./:/nakama/data
entrypoint:
  - /bin/sh
  - -ecx
  - >
    /nakama/nakama migrate up --database.address root@cockroachdb:26257 &&
    exec /nakama/nakama --name nakama1 --database.address root@cockroachdb:26257
    --runtime.path /nakama/data/data/modules
    --runtime.js_entrypoint character.js
```

**Why these settings?**
- `./:/nakama/data` - Mounts repo root to `/nakama/data/` in container
- `--runtime.path /nakama/data/data/modules` - Points to modules directory
- `--runtime.js_entrypoint character.js` - Specifies which JS file to load

## Troubleshooting

### Modules not loading in Nakama

```powershell
# 1. Verify compilation succeeded
npm run build

# 2. Check JavaScript files exist
ls data\modules\*.js

# 3. Check Nakama logs for errors
docker compose logs nakama | Select-String "runtime|module|error"
```

### TypeScript compilation errors

```powershell
# Manually compile to see detailed errors
npx tsc data\modules\character\character.ts --target ES2015 --module commonjs
```

### Clean rebuild

```powershell
# Remove all compiled files
.\dev.ps1 clean

# Fresh build and start
.\dev.ps1 up-build
```

### Container won't start

```powershell
# Check for port conflicts
netstat -an | Select-String "7349|7350|7351|26257|9090"

# Full reset
docker compose down --volumes
.\dev.ps1 up-build
```

## File Ownership & Permissions

The compiled JavaScript files are:
- ✅ Generated automatically by build scripts
- ✅ Gitignored (not tracked in version control)
- ✅ Recreated on every build
- ❌ Should NOT be manually edited (edit `.ts` files instead)

## Performance

- **TypeScript compilation**: ~1-2 seconds (single module)
- **Watch mode incremental**: ~100-300ms
- **Container restart**: ~2-3 seconds
- **Full stack startup**: ~10-15 seconds

## Next Steps

- See `data/modules/README.md` for detailed TypeScript build documentation
- See `.kiro/specs/docker-compose-local-build/` for feature specifications
- See main `README.md` for Nakama usage documentation
