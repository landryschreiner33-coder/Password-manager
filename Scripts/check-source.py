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
# XCSwiftPackageProductDependency.package is a remote-package reference, not
# XCLocalSwiftPackageReference. An invalid edge can leave the app unable to load
# a module that SwiftPM built successfully.
objects = dict(re.findall(r'^([A-F0-9]{24}) = \{ (.*?) \};$', text, re.M))
for object_id, body in objects.items():
    if 'isa = XCSwiftPackageProductDependency;' in body:
        package = re.search(r'\bpackage = ([A-F0-9]{24});', body)
        if package:
            assert 'isa = XCRemoteSwiftPackageReference;' in objects[package[1]], 'Product dependency has a non-remote package reference'
# Match SwiftPM's Debug architecture to the selected Mac; Release remains universal.
for body in objects.values():
    if 'isa = XCBuildConfiguration;' in body and 'SDKROOT = "macosx";' in body:
        expected = 'YES' if 'name = Debug;' in body else 'NO'
        assert f'ONLY_ACTIVE_ARCH = "{expected}";' in body, 'App and package architecture settings may diverge'
ET.parse(root/'Stillwater.xcodeproj/xcshareddata/xcschemes/Stillwater.xcscheme')
print(f'PASS: {len(manifest)} pinned dependency files, plists, entitlements, scheme XML, and deterministic project references.')
