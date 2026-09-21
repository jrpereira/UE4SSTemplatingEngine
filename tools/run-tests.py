"""Run TE's offline Lua suites with an explicitly available Lua 5.4 runtime."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--lua', default=os.environ.get('LUA') or shutil.which('lua'))
args = parser.parse_args()
if not args.lua:
    parser.error('Lua 5.4 required: pass --lua or set LUA')
version = subprocess.run([args.lua, '-v'], text=True, capture_output=True, check=True)
if 'Lua 5.4' not in version.stdout + version.stderr:
    parser.error('Lua 5.4 required')
for directory in ('work', 'outputs'):
    (ROOT / directory).mkdir(exist_ok=True)
files = sorted(ROOT.glob('Scripts/**/*.lua')) + [ROOT / 'categories.lua']
for path in files:
    env = dict(os.environ, TE_SYNTAX_FILE=str(path))
    subprocess.run([args.lua, '-e', 'assert(loadfile(os.getenv("TE_SYNTAX_FILE")))'], cwd=ROOT, env=env, check=True)
tests = sorted(ROOT.glob('tests/*_test.lua'))
for path in tests:
    subprocess.run([args.lua, str(path)], cwd=ROOT, check=True)
print(f'PASS: {len(files)} source syntax checks, {len(tests)} Lua suites')
