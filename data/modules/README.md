# TypeScript Runtime Modules - Build System

Automated TypeScript compilation for Nakama runtime modules.

## Quick Start

### Windows (PowerShell)

```powershell
# Build modules and start stack
.\dev.ps1 up

# Build and start with image rebuild
.\dev.ps1 up-build

# Watch for TypeScript changes (auto-compile)
.\dev.ps1 watch-modules

# Restart Nakama after code changes
.\dev.ps1 restart

# View all commands
.\dev.ps1 help
```

### Linux/Mac (Make)

```bash
# Build modules and start stack
make up

# Build and start with image rebuild
make up-build

# Watch for TypeScript changes (auto-compile)
make watch-modules

# Restart Nakama after code changes
make restart

# View all commands
make help
```

### Using npm directly

```bash
# Build all TypeScript modules once
npm run build

# Watch for changes and auto-compile
npm run watch

# Build and start Docker Compose
npm run dev

# Build and start with image rebuild
npm run dev:build
```

## How It Works

1. **TypeScript Source**: Write your runtime modules in TypeScript under `data/modules/<module-name>/`
   - Example: `data/modules/character/character.ts`

2. **Automatic Compilation**: The build system:
   - Finds all `.ts` files in `data/modules/`
   - Compiles them to JavaScript (ES2015, CommonJS)
   - Copies the compiled `.js` files to `data/modules/` root

3. **Nakama Loading**: Nakama loads JavaScript files from `/nakama/data/data/modules/`
   - Configured via `--runtime.js_entrypoint character.js`

## Development Workflow

### Recommended: Watch Mode

For active development, use watch mode to automatically compile on save:

```powershell
# Terminal 1: Watch and auto-compile TypeScript
.\dev.ps1 watch-modules

# Terminal 2: Run Docker Compose
docker compose up
```

When you modify any `.ts` file, it will automatically compile and copy to the modules root. Then restart Nakama:

```powershell
docker compose restart nakama
```

### Alternative: Manual Rebuild

```powershell
# 1. Modify TypeScript files
# 2. Rebuild and restart
.\dev.ps1 restart
```

## File Structure

```
data/modules/
├── character/
│   ├── character.ts       # TypeScript source
│   ├── character.js       # Compiled (gitignored)
│   └── README.md
├── character.js           # Copied to root for Nakama (gitignored)
├── build.sh               # Bash build script
├── build.ps1              # PowerShell build script
└── ...other modules
```

## Configuration Files

- **`package.json`**: Node.js dependencies and npm scripts
- **`build-modules.js`**: Main build script (cross-platform)
- **`dev.ps1`**: PowerShell helper commands
- **`Makefile`**: Make helper commands (Linux/Mac)
- **`docker-compose.yml`**: Configured with `--runtime.js_entrypoint`

## Troubleshooting

### Modules not loading

1. Check compilation succeeded:
   ```powershell
   npm run build
   ```

2. Verify JavaScript files exist:
   ```powershell
   ls data\modules\*.js
   ```

3. Check Nakama logs:
   ```powershell
   docker compose logs nakama | Select-String "runtime|module"
   ```

### TypeScript compilation errors

- Ensure TypeScript is installed: `npm install`
- Check TypeScript version: `npx tsc --version`
- Manually compile for detailed errors:
  ```powershell
  npx tsc data\modules\character\character.ts --target ES2015 --module commonjs
  ```

### Clean start

```powershell
# Remove all compiled JavaScript
.\dev.ps1 clean

# Rebuild from scratch
.\dev.ps1 build-modules
docker compose up --build
```

## Adding New Modules

1. Create new TypeScript file:
   ```powershell
   mkdir data\modules\combat
   # Create data\modules\combat\combat.ts
   ```

2. Build:
   ```powershell
   npm run build
   ```

3. Update `docker-compose.yml` entrypoint if needed (for multi-module entrypoints)

4. Restart Nakama:
   ```powershell
   docker compose restart nakama
   ```

## CI/CD Integration

For automated builds in CI/CD:

```bash
# Install dependencies
npm ci

# Build TypeScript modules
npm run build

# Start services
docker compose up -d
```

## Performance

- **Cold build**: ~1-2 seconds for single module
- **Watch mode**: ~100-300ms incremental compile
- **Hot reload**: Requires Nakama container restart (~2-3 seconds)

## Future Enhancements

- [ ] True hot reload without container restart (experimental)
- [ ] TypeScript type checking (currently using `--skipLibCheck`)
- [ ] Source maps for debugging
- [ ] Minification for production builds
