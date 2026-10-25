#!/usr/bin/env python3
"""Package the built app and sign both archive and appcast with the Keychain key."""
from pathlib import Path
import datetime
import email.utils
import plistlib
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
app = root / 'dist/Pomolet.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
archive = root / 'dist/Pomolet-macOS.zip'
if archive.exists():
    archive.unlink()
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
signer = str(root / '.build/sparkle/bin/sign_update')
signature = subprocess.check_output([signer, '--account', 'Pomolet', '-p', str(archive)], text=True).strip()
subprocess.run([signer, '--account', 'Pomolet', '--verify', str(archive), signature], check=True)
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
feed = ET.Element('rss', version='2.0')
channel = ET.SubElement(feed, 'channel')
ET.SubElement(channel, 'title').text = 'Pomolet Updates'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = f'Pomolet {version}'
ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
ET.SubElement(item, f'{{{ns}}}version').text = build
ET.SubElement(item, f'{{{ns}}}shortVersionString').text = version
ET.SubElement(item, f'{{{ns}}}minimumSystemVersion').text = '14.0'
ET.SubElement(item, 'enclosure', {
    'url': f'https://github.com/Davied-H/Pomolet/releases/download/v{version}/{archive.name}',
    'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
    f'{{{ns}}}edSignature': signature,
})
appcast = root / 'dist/appcast.xml'
ET.indent(feed)
ET.ElementTree(feed).write(appcast, encoding='utf-8', xml_declaration=True)
subprocess.run([signer, '--account', 'Pomolet', str(appcast)], check=True)
subprocess.run([signer, '--account', 'Pomolet', '--verify', str(appcast)], check=True)
print(f'Ready: {archive}\nReady: {appcast}')
