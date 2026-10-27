#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
cc -O2 -DARGON2_NO_THREADS -IScripts/ReferenceArgon2/include -IScripts/ReferenceArgon2 \
  Scripts/ReferenceArgon2/argon2.c Scripts/ReferenceArgon2/core.c \
  Scripts/ReferenceArgon2/encoding.c Scripts/ReferenceArgon2/ref.c \
  Scripts/ReferenceArgon2/thread.c Scripts/ReferenceArgon2/blake2/blake2b.c \
  Scripts/argon2-upstream-tests.c -o "$build_dir/argon2-tests"
"$build_dir/argon2-tests"
