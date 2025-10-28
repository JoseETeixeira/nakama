#!/usr/bin/env node

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const MODULES_DIR = path.join(__dirname, 'data', 'modules');
const WATCH_MODE = process.argv.includes('--watch');

console.log('🔨 Building TypeScript runtime modules...\n');

/**
 * Compile a single TypeScript file
 */
function compileTypeScript(tsFile) {
  const dir = path.dirname(tsFile);
  const filename = path.basename(tsFile, '.ts');
  const jsFile = path.join(dir, `${filename}.js`);
  const destFile = path.join(MODULES_DIR, `${filename}.js`);

  try {
    console.log(`  → Compiling: ${filename}.ts`);

    // Compile TypeScript
    execSync(`npx tsc "${tsFile}" --target ES2015 --module commonjs --skipLibCheck`, {
      stdio: 'pipe'
    });

    // Copy to modules root
    if (fs.existsSync(jsFile)) {
      fs.copyFileSync(jsFile, destFile);
      console.log(`  ✓ Copied ${filename}.js to modules root`);
    }
  } catch (error) {
    console.error(`  ✗ Error compiling ${filename}.ts:`, error.message);
  }
}

/**
 * Find and compile all TypeScript modules
 */
function buildAll() {
  const findTsFiles = (dir) => {
    const files = [];
    const entries = fs.readdirSync(dir, { withFileTypes: true });

    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        files.push(...findTsFiles(fullPath));
      } else if (entry.isFile() && entry.name.endsWith('.ts')) {
        files.push(fullPath);
      }
    }

    return files;
  };

  const tsFiles = findTsFiles(MODULES_DIR);

  if (tsFiles.length === 0) {
    console.log('No TypeScript files found.');
    return;
  }

  tsFiles.forEach(compileTypeScript);
  console.log(`\n✅ Built ${tsFiles.length} module(s)\n`);
}

/**
 * Watch mode for development
 */
function watchMode() {
  const chokidar = require('chokidar');

  console.log('👀 Watching for TypeScript changes...\n');

  const watcher = chokidar.watch(path.join(MODULES_DIR, '**', '*.ts'), {
    persistent: true,
    ignoreInitial: false
  });

  watcher.on('change', (tsFile) => {
    console.log(`\n📝 File changed: ${path.basename(tsFile)}`);
    compileTypeScript(tsFile);
  });

  watcher.on('add', (tsFile) => {
    console.log(`\n➕ File added: ${path.basename(tsFile)}`);
    compileTypeScript(tsFile);
  });
}

// Main execution
if (WATCH_MODE) {
  buildAll();
  watchMode();
} else {
  buildAll();
}
