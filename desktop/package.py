"""Build and package a universal Mac release with instructions and a checksum."""
from pathlib import Path
import hashlib
import plistlib
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent
subprocess.run([sys.executable, str(root / 'build.py'), '--universal'], check=True)
app = root / 'output' / '兔兔喝水.app'
with (app / 'Contents' / 'Info.plist').open('rb') as file:
    version = plistlib.load(file)['CFBundleShortVersionString']
name = f'TutuWater-v{version}-macOS-universal'
release = root / 'output' / 'releases'
release.mkdir(parents=True, exist_ok=True)
archive = release / f'{name}.zip'
with tempfile.TemporaryDirectory(prefix='tutu-release-') as directory:
    package = Path(directory) / name
    package.mkdir()
    shutil.copytree(app, package / app.name)
    shutil.copy2(root / '使用说明.md', package / '使用说明.md')
    subprocess.run(['ditto', '--norsrc', '--noextattr', '-c', '-k', '--keepParent',
                    str(package), str(archive)], check=True)
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
(release / 'SHA256SUMS.txt').write_text(f'{digest}  {archive.name}\n')
print(archive)
print(f'SHA256: {digest}')
