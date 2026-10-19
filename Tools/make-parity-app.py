from pathlib import Path
import plistlib,subprocess,tempfile,shutil
root=Path(__file__).resolve().parents[1]
source=root/'dist/Pomolet.app';target=root/'.build/Pomolet QA.app'
subprocess.run(['ditto',str(source),str(target)],check=True)
fixture=Path(tempfile.gettempdir())/'focus-native-parity-state.json'
shutil.copyfile(root/'.build/parity-fixture/state.json',fixture)
plist=target/'Contents/Info.plist';data=plistlib.loads(plist.read_bytes())
data.update(CFBundleIdentifier='com.dong.focusnative.parity',CFBundleName='Pomolet QA',CFBundleDisplayName='Pomolet QA',FocusFixturePath=str(fixture))
plist.write_bytes(plistlib.dumps(data,sort_keys=False))
subprocess.run(['codesign','--force','--deep','--sign','-','--timestamp=none',str(target)],check=True)
print(target)
