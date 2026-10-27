#!/bin/bash
# Preserve xcodebuild's result and surface diagnostics in GitHub's run summary.
set -uo pipefail
log_file=$(mktemp)
trap 'rm -f "$log_file"' EXIT
xcodebuild "$@" 2>&1 | tee "$log_file"
statuses=("${PIPESTATUS[@]}")
if [ "${statuses[0]}" -ne 0 ]; then
    python3 - "$log_file" <<'PY'
import re
import sys
from pathlib import Path
lines = Path(sys.argv[1]).read_text(errors='replace').splitlines()
diagnostics = [line for line in lines if re.search(r'\berror:|Unable to resolve module|Module file .*not', line)]
if not diagnostics:
    diagnostics = ['xcodebuild failed; inspect the failed build step for details.']
for line in list(dict.fromkeys(diagnostics))[:20]:
    text = line[:3000].replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print('::error title=Xcode build diagnostic::' + text)
PY
    exit "${statuses[0]}"
fi
if [ "${statuses[1]}" -ne 0 ]; then
    exit "${statuses[1]}"
fi
