#!/usr/bin/env python3
from pathlib import Path
import json
import plistlib
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
project = json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(root/'PocketLedger.xcodeproj/project.pbxproj')]))
objects = project['objects']
for value in objects.values():
    if value['isa'] == 'PBXFileReference' and value.get('sourceTree') == 'SOURCE_ROOT':
        assert (root/value['path']).exists(), f"Missing project file: {value['path']}"
sources = next(v for v in objects.values() if v['isa'] == 'PBXSourcesBuildPhase')
compiled = {objects[objects[key]['fileRef']]['path'] for key in sources['files']}
expected = {str(p.relative_to(root)) for area in ['App', 'Sources'] for p in (root/area).rglob('*.swift')}
assert compiled == expected, f'Unregistered Swift files: {expected - compiled}'
for path in (root/'App/Resources').rglob('*'):
    if path.suffix in ['.plist', '.entitlements', '.xcprivacy']:
        with path.open('rb') as f: plistlib.load(f)
    if path.name == 'Contents.json': json.loads(path.read_text())
for path in (root/'PocketLedger.xcodeproj/xcshareddata/xcschemes').glob('*.xcscheme'):
    scheme = ET.parse(path)
    for reference in scheme.iter('BuildableReference'):
        assert reference.attrib['BlueprintIdentifier'] in objects
icon = root/'App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
assert icon.exists(), 'Missing app icon'
assert (root/'Config/Debug.xcconfig').read_text().find('LEDGER_CLOUD_ENABLED = NO') >= 0
assert (root/'Config/CloudDebug.xcconfig').read_text().find('LEDGER_CLOUD_ENABLED = YES') >= 0
print(f'Project validated: {len(compiled)} app source files, resource plists, assets, and signing schemes.')
