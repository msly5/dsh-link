#!/usr/bin/env python3
"""Prepare private configuration without modifying cloud resources or starting services."""
from private_config import protect_directory
import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--config-dir', type=Path, default=Path(os.environ.get('DSH_REMOTE_CONFIG_DIR', Path.home()/'.config/dsh-remote')))
args = parser.parse_args()
directory = args.config_dir.expanduser().resolve()
if directory == ROOT or ROOT in directory.parents:
    raise SystemExit('Keep private configuration outside the repository.')
protect_directory(directory)
config = directory/'bridge.env'
if not config.exists():
    with config.open('x') as out:
        out.write((ROOT/'bridge/bridge.env.example').read_text())
    config.chmod(0o600)
    print('Created private bridge.env template. Fill the team domain and application AUD before starting.')
else:
    print('Existing bridge.env preserved.')
for executable in ['node','npm','cloudflared','xcodebuild']:
    print(f'{executable}: {"FOUND" if shutil.which(executable) else "MISSING"}')
node = shutil.which('node')
if node:
    major = int(subprocess.check_output([node, '-p', 'process.versions.node.split(".")[0]'], text=True))
    if major < 22: raise SystemExit('Node.js 22 or later is required.')
print('Configuration directory:', directory)
print('Next: npm ci --ignore-scripts --prefix bridge; follow docs/cloudflare.md.')
