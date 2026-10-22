#!/usr/bin/env python3
"""Validate generated update metadata and its package signature, offline."""
import base64
import pathlib
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET

feed, archive, info_path = map(pathlib.Path, sys.argv[1:])
with info_path.open('rb') as stream:
    info = plistlib.load(stream)
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
item = ET.parse(feed).find('./channel/item')
assert item is not None, 'Missing appcast item'
assert item.findtext('sparkle:version', namespaces=ns) == info['CFBundleVersion'], 'Build mismatch'
assert item.findtext('sparkle:shortVersionString', namespaces=ns) == info['CFBundleShortVersionString'], 'Version mismatch'
enclosure = item.find('enclosure')
assert enclosure is not None, 'Missing enclosure'
expected_url = f"https://github.com/frank-yf/auralim-mac/releases/download/v{info['CFBundleShortVersionString']}/{archive.name}"
assert enclosure.attrib['url'] == expected_url, 'Archive must use the immutable release tag URL'
assert int(enclosure.attrib['length']) == archive.stat().st_size, 'Size mismatch'
signature = enclosure.attrib[f"{{{ns['sparkle']}}}edSignature"]
assert len(base64.b64decode(signature, validate=True)) == 64, 'Invalid signature length'
tools = pathlib.Path(__file__).resolve().parent.parent / '.build/artifacts/sparkle/Sparkle/bin'
subprocess.run([str(tools / 'sign_update'), '--account', 'app.duskshift.mac', '--verify', str(archive), signature], check=True)
print('Verified appcast version, build, immutable URL, package size and EdDSA signature')
