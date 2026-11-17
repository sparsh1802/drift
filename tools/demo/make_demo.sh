#!/bin/bash
# Renders the demo video to dist/drift-demo.mp4 (1920×1080, about 1 minute to render).
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/obj dist
swiftc -O $(ls Sources/*.swift | grep -v main.swift) tools/demo/main.swift -o build/obj/drift-demo \
  -framework Cocoa -framework Metal -framework MetalKit -framework IOKit \
  -framework AVFoundation -framework CoreMedia -framework CoreVideo
build/obj/drift-demo dist/drift-demo.mp4
