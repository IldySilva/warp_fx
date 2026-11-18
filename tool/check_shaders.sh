#!/bin/sh
# Compiles every shader for SkSL, Metal and GLES, as `flutter build` would.
set -e
IMP=$(find "$(dirname "$(command -v flutter)")/cache/artifacts/engine" -name impellerc -maxdepth 3 | head -1)
OUT=$(mktemp -d)
for f in "$(dirname "$0")"/../shaders/*.frag; do
  "$IMP" --sksl --runtime-stage-metal --runtime-stage-gles --runtime-stage-vulkan --iplr \
    --input="$f" --sl="$OUT/$(basename "$f").iplr" --spirv="$OUT/$(basename "$f").spv" \
    --include="$(dirname "$IMP")/shader_lib" && echo "ok  $(basename "$f")"
done
