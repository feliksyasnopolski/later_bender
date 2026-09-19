#!/usr/bin/env bash
set -euo pipefail

commands=(
  bash git curl wget jq yq rg fd fzf file xxd hexdump
  cc c++ make cmake ninja clang llvm-config lld gdb strace
  python3 pip3 ruby bundle node npm sqlite3 psql redis-cli
  tar gzip bzip2 xz zstd unzip zip 7z
  shellcheck shfmt xmlstarlet xmllint pandoc identify ffmpeg pdfinfo gs
)

for command_name in "${commands[@]}"; do
  command -v "$command_name" >/dev/null || {
    printf 'missing command: %s\n' "$command_name" >&2
    exit 1
  }
done

locale charmap | grep -qx 'UTF-8'
git --version >/dev/null
curl --version >/dev/null
jq -n '{ok: true}' >/dev/null
python3 -c 'import json; print(json.dumps({"ok": True}))' >/dev/null
ruby -e 'abort unless RUBY_VERSION'
node --version >/dev/null
printf 'workspace image smoke test passed\n'
