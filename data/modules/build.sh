#!/bin/bash
# Automatically compile TypeScript modules to JavaScript
# This script runs before Nakama starts to ensure all TypeScript modules are compiled

set -e

echo "Building TypeScript runtime modules..."

# Find all TypeScript files in subdirectories and compile them
find /nakama/data/data/modules -name "*.ts" -type f | while read -r ts_file; do
    dir=$(dirname "$ts_file")
    filename=$(basename "$ts_file" .ts)

    echo "Compiling: $ts_file"

    # Compile TypeScript to JavaScript
    npx tsc "$ts_file" --target ES2015 --module commonjs --skipLibCheck

    # Copy the compiled JS file to the modules root directory
    if [ -f "${dir}/${filename}.js" ]; then
        cp "${dir}/${filename}.js" "/nakama/data/data/modules/${filename}.js"
        echo "Copied ${filename}.js to modules root"
    fi
done

echo "TypeScript compilation complete!"
