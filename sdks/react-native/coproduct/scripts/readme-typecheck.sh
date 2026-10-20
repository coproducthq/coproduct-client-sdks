#!/usr/bin/env bash
# Type-checks every TypeScript example in the README against the package's
# built types (lib/typescript, from yarn build), the same types an app gets
# from npm. Each example compiles as its own module
#   scripts/readme-typecheck.sh [README]
set -euo pipefail
pkg="$(cd "$(dirname "$0")/.." && pwd)"
cd "$pkg"
readme=${1:-README.md}
if [ ! -f lib/typescript/src/index.d.ts ]; then
  echo "lib/typescript is missing. Fix: run yarn build first." >&2
  exit 2
fi
if grep -nE '^[[:space:]]+```(ts|tsx|typescript)[[:space:]]*$' "$readme" >&2; then
  echo "The fences above are indented, so this check cannot compile them. Fix: move TypeScript examples out of lists, unindented." >&2
  exit 1
fi
out=build/readme-typecheck
rm -rf "$out"
mkdir -p "$out"
awk -v out="$out" '
  /^```(ts|tsx|typescript)[[:space:]]*$/ { n++; ext = ($0 ~ /tsx/) ? "tsx" : "ts"; f = sprintf("%s/example%02d.%s", out, n, ext); inside = 1; next }
  /^```/ { if (inside) print "export {};" > f; inside = 0; next }
  inside { print > f }
' "$readme"
count=$(find "$out" -name 'example*' | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then
  echo "$readme has no TypeScript examples to check." >&2
  exit 1
fi
cp scripts/readme-context/*.d.ts "$out/"
cat > "$out/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "strict": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "target": "ESNext",
    "lib": ["ESNext"],
    "skipLibCheck": true,
    "customConditions": ["react-native-strict-api"],
    "types": []
  },
  "include": ["*.ts", "*.tsx"]
}
EOF
if node_modules/.bin/tsc -p "$out/tsconfig.json"; then
  echo "README examples compile: $count examples in $readme"
else
  echo "Fix: correct the README examples above so they match the SDK's API. The failing file names the example's position in the README." >&2
  exit 1
fi
