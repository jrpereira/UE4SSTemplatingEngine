"""Validate the active MCT lifecycle runtime and menu integration."""
import argparse
import os
import tempfile
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--lua', default=shutil.which('lua5.4') or shutil.which('lua'))
parser.add_argument('--dmm-choices', default=os.getenv('MCT_DMM_CHOICES'))
parser.add_argument('--presentation', default=os.getenv('MCT_PRESENTATION'))
args = parser.parse_args()
if not args.dmm_choices or not args.presentation:
    parser.error('menu tests require --dmm-choices and --presentation (or MCT_DMM_CHOICES and MCT_PRESENTATION)')
if not args.lua:
    parser.error('Lua 5.4 required')
version = subprocess.run([args.lua, '-v'], capture_output=True, text=True, check=True)
if 'Lua 5.4' not in version.stdout + version.stderr:
    parser.error('Lua 5.4 required')
files = (sorted(ROOT.glob('Scripts/mc/*.lua')) + sorted(ROOT.glob('Scripts/categories/*.lua'))
         + [ROOT / 'Scripts/mc.lua']
         + [ROOT / 'Scripts/dmm_extension.lua', ROOT / 'Scripts/main.lua',
            ROOT / 'Scripts/categories/mc.lua'])
for path in files:
    subprocess.run([args.lua, '-e', 'assert(loadfile(arg[1]))', '-', str(path)], cwd=ROOT, check=True)
with tempfile.TemporaryDirectory(prefix='mct-menu-tests-') as directory:
    env = dict(os.environ, MCT_TEST_DIR=directory, MCT_DMM_CHOICES=str(Path(args.dmm_choices).resolve()),
               MCT_PRESENTATION=str(Path(args.presentation).resolve()))
    for path in sorted(ROOT.glob('tests/mc/*_test.lua')):
        subprocess.run([args.lua, str(path)], cwd=ROOT, env=env, check=True)
print(f'PASS: {len(files)} runtime/category syntax checks')
