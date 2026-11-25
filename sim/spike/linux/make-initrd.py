"""Build a small RV64 BusyBox newc initramfs without sudo, chroot or binfmt."""
from pathlib import Path
from tempfile import TemporaryDirectory
import hashlib
import itertools
import os
import argparse
import subprocess
import urllib.request

here = Path(__file__).resolve().parent
out = here.parent / 'build/linux'
out.mkdir(exist_ok=True, parents=True)
deb = out/'busybox-rv64.deb'
sha = '71cc910853f67ee183fa3c188583a39bee5df4dbfe31bd0bd6958458f0d73990'
url = 'https://ports.ubuntu.com/ubuntu-ports/pool/main/b/busybox/busybox-static_1.36.1-6ubuntu3.1_riscv64.deb'
if not deb.exists():
    urllib.request.urlretrieve(url, deb)
if hashlib.sha256(deb.read_bytes()).hexdigest() != sha:
    raise SystemExit(f'BusyBox SHA256 mismatch: {deb}')
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--drm', action='store_true', help='add the DRM module and static guest KMS test')
args = p.parse_args()
if args.drm:
    out = out/'drm'
    if not (out/'glanda_drm.ko').is_file(): raise SystemExit('First run bash linux/build-drm.sh')
    subprocess.run([os.environ.get('CROSS_COMPILE', 'riscv64-linux-gnu-')+'gcc', '-std=c11',
                    '-O2', '-Wall', '-Wextra', '-static', here/'kms-test.c', '-o', out/'kms-test'], check=True)
archive = bytearray()
ino = itertools.count(1)
def entry(name, mode, data=b'', major=0, minor=0):
    name = name.encode() + b'\0'
    fields = (next(ino), mode, 0, 0, 1, 0, len(data), 0, 0, major, minor, len(name), 0)
    archive.extend(b'070701' + ''.join(f'{i:08x}' for i in fields).encode() + name)
    archive.extend(b'\0' * (-len(archive) % 4)); archive.extend(data)
    archive.extend(b'\0' * (-len(archive) % 4))
for name in ('bin','dev','proc','sys','tmp'):
    entry(name, 0o040755)
with TemporaryDirectory() as tmp:
    subprocess.run(['dpkg-deb', '-x', deb, tmp], check=True)
    entry('bin/busybox', 0o100755, (Path(tmp)/'usr/bin/busybox').read_bytes())
entry('bin/sh', 0o120777, b'busybox')
entry('dev/console', 0o020600, major=5, minor=1)
entry('dev/null', 0o020666, major=1, minor=3)
if args.drm:
    entry('glanda_drm.ko', 0o100644, (out/'glanda_drm.ko').read_bytes())
    entry('bin/kms-test', 0o100755, (out/'kms-test').read_bytes())
entry('init', 0o100755, (here/'init').read_bytes()); entry('TRAILER!!!', 0)
archive.extend(b'\0' * (-len(archive) % 512))
target = out/'initramfs.cpio'
target.write_bytes(archive)
print(target)
