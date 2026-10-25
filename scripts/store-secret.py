#!/usr/bin/env python3
"""Store local secrets via hidden input; no values in command arguments or terminal output."""
from private_config import protect_directory
import argparse
import getpass
import json
import os
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('kind', choices=['tunnel', 'client'])
p.add_argument('--config-dir', type=Path, default=Path(os.environ.get('DSH_REMOTE_CONFIG_DIR', Path.home()/'.config/dsh-remote')))
a = p.parse_args(); directory = a.config_dir.expanduser().resolve()
if directory == ROOT or ROOT in directory.parents: raise SystemExit('Secrets must be outside the repository.')
protect_directory(directory)
destination = directory/('tunnel.token' if a.kind == 'tunnel' else 'client.json')
if destination.exists(): raise SystemExit('File already exists. Revoke/rotate explicitly before replacing it.')
if a.kind == 'tunnel':
    content = getpass.getpass('Tunnel token (hidden): ').strip()
    if not content or any(c.isspace() for c in content): raise SystemExit('Invalid token input.')
else:
    url = input('Public HTTPS server URL: ').strip().rstrip('/')
    parsed = urlsplit(url)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise SystemExit('Use an HTTPS URL without user info, query or fragment.')
    identity = getpass.getpass('Service Token Client ID (hidden): ').strip()
    secret = getpass.getpass('Service Token Client Secret (hidden): ').strip()
    if not identity or not secret or any(c.isspace() for c in identity+secret): raise SystemExit('Incomplete credentials.')
    content = json.dumps({'server_url':url, 'client_id':identity, 'client_secret':secret})
# Open exclusively with 0600 from the first write, rather than chmod after storing a secret.
fd = os.open(destination, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as f: f.write(content+'\n')
print('Private secret file saved. Values were not displayed.')
