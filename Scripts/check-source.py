#!/usr/bin/env python3
"""Dependency integrity and project consistency checks; not a Swift type checker."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET
root = Path(__file__).resolve().parents[1]
manifest = json.loads((root/'Docs/argon2-checksums.json').read_text()) | json.loads((root/'Docs/sodium-checksums.json').read_text())
for name, expected in manifest.items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest() == expected, name
for name in ['App/Info.plist','App/Stillwater.entitlements']:
    with (root/name).open('rb') as handle: plistlib.load(handle)
entitlements=plistlib.loads((root/'App/Stillwater.entitlements').read_bytes())
assert entitlements == {'com.apple.security.app-sandbox': True, 'com.apple.security.files.user-selected.read-write': True}
project=root/'Stillwater.xcodeproj/project.pbxproj'
before=project.read_bytes()
subprocess.run(['python3',str(root/'Scripts/generate-project.py')],check=True)
assert project.read_bytes()==before, 'Project was stale; regeneration updated it. Review and rerun.'
text=project.read_text()
defined=re.findall(r'^([A-F0-9]{24}) = ',text,re.M)
assert len(defined)==len(set(defined))
assert set(re.findall(r'\b[A-F0-9]{24}\b',text))==set(defined), 'Dangling project references'
ET.parse(root/'Stillwater.xcodeproj/xcshareddata/xcschemes/Stillwater.xcscheme')
print(f'PASS: {len(manifest)} pinned dependency files, plists, entitlements, scheme XML, and deterministic project references.')
