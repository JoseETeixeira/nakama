#!/bin/sh
set -e

echo "========================================="
echo "Starting Nakama with TypeScript support"
echo "========================================="

# Check if Node.js and TypeScript are available
if command -v node > /dev/null 2>&1; then
    echo "Node.js found: $(node --version)"

    # Install TypeScript if not available
    if ! command -v tsc > /dev/null 2>&1; then
        echo "Installing TypeScript..."
        npm install -g typescript
    fi

    echo "TypeScript version: $(tsc --version)"

    # Compile all TypeScript modules
    echo "Compiling TypeScript modules..."
    find /nakama/data/data/modules -name "*.ts" -type f | while read -r ts_file; do
        dir=$(dirname "$ts_file")
        filename=$(basename "$ts_file" .ts)

        echo "  → Compiling: $filename.ts"
        tsc "$ts_file" --target ES2015 --module commonjs --skipLibCheck 2>/dev/null || true

        # Copy to modules root if compilation succeeded
        if [ -f "${dir}/${filename}.js" ]; then
            cp "${dir}/${filename}.js" "/nakama/data/data/modules/${filename}.js"
            echo "  ✓ Copied ${filename}.js to modules root"
        fi
    done

    echo "TypeScript compilation complete!"
else
    echo "WARNING: Node.js not found in container. Skipping TypeScript compilation."
    echo "Using pre-compiled JavaScript files if available."
fi

echo "========================================="

# Run migrations and start Nakama
/nakama/nakama migrate up --database.address root@cockroachdb:26257 && \
exec /nakama/nakama --name nakama1 --database.address root@cockroachdb:26257 --logger.level DEBUG --session.token_expiry_sec 7200 --metrics.prometheus_port 9100 --runtime.path /nakama/data/data/modules --runtime.js_entrypoint character.js
