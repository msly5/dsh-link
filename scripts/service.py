#!/usr/bin/env python3
"""Install/remove per-user macOS LaunchAgents with no embedded secret values."""
import argparse
import os
import json
import socket
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('action', choices=['install','uninstall'])
p.add_argument('--config-dir', type=Path, default=Path(os.environ.get('DSH_REMOTE_CONFIG_DIR', Path.home()/'.config/dsh-remote')))
a = p.parse_args()
if sys.platform != 'darwin': raise SystemExit('This installer is for macOS LaunchAgents only.')
directory = a.config_dir.expanduser().resolve()
if directory == ROOT or ROOT in directory.parents: raise SystemExit('Private configuration must be outside the repository.')
launch = Path.home()/'Library/LaunchAgents'; launch.mkdir(parents=True, exist_ok=True)
domain = f'gui/{os.getuid()}'
labels = ['app.dshremote.bridge', 'app.dshremote.tunnel']
if a.action == 'uninstall':
    for label in labels:
        file = launch/f'{label}.plist'
        if file.exists():
            subprocess.run(['launchctl','bootout',domain,str(file)],check=False,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            file.unlink()
    print('Removed dsh remote LaunchAgents; private configuration and DSH are preserved.')
    raise SystemExit(0)
node = shutil.which('node'); cloudflared = shutil.which('cloudflared')
if not node or not cloudflared: raise SystemExit('Install Node.js >=22 and cloudflared first.')
if not (directory/'bridge.env').exists() or not (directory/'tunnel.token').exists(): raise SystemExit('Complete private bridge.env and tunnel.token first.')
if not (ROOT/'bridge/node_modules/jose').exists(): raise SystemExit('Run npm ci --ignore-scripts --prefix bridge first.')
# Refuse accidental replacement of existing registrations; explicitly uninstall first.
for label in labels:
    if (launch/f'{label}.plist').exists(): raise SystemExit('LaunchAgents already exist; uninstall before reinstalling.')
environment = {**os.environ, 'DSH_REMOTE_CONFIG_DIR':str(directory)}
code = 'import {loadConfig} from ' + json.dumps((ROOT/'bridge/src/config.mjs').as_uri()) + '; process.stdout.write(String(loadConfig().port));'
port = int(subprocess.check_output([node,'--input-type=module','-e',code],env=environment,text=True))
try:
    with socket.socket() as probe: probe.bind(('127.0.0.1',port))
except OSError:
    raise SystemExit('Bridge port is in use. Stop your foreground bridge or choose another port; no existing process was stopped.')
subprocess.run([node,str(ROOT/'bridge/src/doctor.mjs')],env={**os.environ,'DSH_REMOTE_CONFIG_DIR':str(directory)},check=True)
for label,command in zip(labels, [[node,str(ROOT/'bridge/src/index.mjs')],['/bin/sh',str(ROOT/'scripts/run-tunnel.sh')]]):
    data = {'Label':label,'ProgramArguments':command,'WorkingDirectory':str(ROOT),
            'EnvironmentVariables':{'DSH_REMOTE_CONFIG_DIR':str(directory),'CLOUDFLARED_BIN':cloudflared},
            'RunAtLoad':True,'KeepAlive':True,'ThrottleInterval':10,'Umask':63,
            'StandardOutPath':str(directory/(label+'.out.log')),'StandardErrorPath':str(directory/(label+'.err.log'))}
    file = launch/f'{label}.plist'
    with file.open('xb') as f: plistlib.dump(data,f)
    file.chmod(0o600)
    subprocess.run(['launchctl','bootstrap',domain,str(file)],check=True)
print('Installed user LaunchAgents. Keep the repository at its current path; verify Cloudflare and the iOS connection test.')
