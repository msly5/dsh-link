#!/usr/bin/env python3
"""Conservative release preflight. Reports locations/rule names, never secret values."""
import argparse
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SKIP = {'.git','node_modules','build','.build','.swiftpm','DerivedData','__pycache__','xcuserdata'}
FORBIDDEN = {'Secrets.swift','client.json','device.json','tunnel.token','Local.xcconfig','.credentials.yaml'}
RULES = [
    ('private-key', re.compile(rb'-----BEGIN (?:[A-Z ]+)?PRIVATE KEY-----')),
    ('github-token', re.compile(rb'\bgh[pousr]_[A-Za-z0-9]{24,}\b|github_pat_[A-Za-z0-9_]{30,}')),
    ('jwt-token', re.compile(rb'\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\b')),
    ('personal-home-path', re.compile(rb'/Users/[A-Za-z0-9_.-]+/')),
    ('literal-credential', re.compile(rb'''(?i)(?:client[_-]?secret|accessClientSecret|accessClientId|api[_-]?key|api[_-]?token|tunnel[_-]?token)["']?\s*[:=]\s*["']([A-Za-z0-9_+/=.-]{24,})["']''')),
    ('personal-signing-team', re.compile(rb'\bDEVELOPMENT_TEAM\s*=\s*([A-Z0-9]{10})\s*;')),
]
PLACEHOLDER = re.compile(rb'(?i)example|replace|your|placeholder|test|fixture')

def findings(name, data):
    path = Path(name)
    if path.name in FORBIDDEN or path.suffix.lower() in {'.p8','.p12','.pem','.key','.mobileprovision','.ipa','.log'} or (path.name.startswith('.env') and not path.name.endswith('.example')) or (path.suffix == '.env'):
        yield (name, 1, 'private-file')
    if b'\0' in data[:8192]:
        return  # Binary assets need manual inspection; do not misinterpret compressed bytes as text.
    for rule, pattern in RULES:
        for match in pattern.finditer(data):
            value = match.group(1) if match.lastindex else match.group()
            if rule in {'literal-credential','personal-signing-team'} and PLACEHOLDER.search(value): continue
            yield (name, data[:match.start()].count(b'\n')+1, rule)

def git(*args):
    return subprocess.check_output(['git','-C',str(ROOT),*args], stderr=subprocess.DEVNULL)

def scan(staged=False):
    in_git = False
    try: in_git = git('rev-parse','--show-toplevel').decode().strip() == str(ROOT)
    except subprocess.CalledProcessError: pass
    if staged and not in_git: raise ValueError('--staged requires a repository rooted at this project.')
    if in_git:
        raw = git('diff','--cached','--name-only','--diff-filter=ACMR','-z') if staged else git('ls-files','--cached','--others','--exclude-standard','-z')
        names = sorted(set(p.decode() for p in raw.split(b'\0') if p))
    else:
        names = sorted(str(p.relative_to(ROOT)) for p in ROOT.rglob('*') if p.is_file() and not any(part in SKIP for part in p.relative_to(ROOT).parts))
    found=[]; count=0
    for name in names:
        file = ROOT/name
        if not staged and not file.exists(): continue
        if (file.is_symlink() if not staged else git('ls-files','-s','--',name).startswith(b'120000')):
            found.append((name,1,'symlink-requires-review')); continue
        data = git('show',f':{name}') if staged else file.read_bytes()
        if len(data)>4*1024*1024: found.append((name,1,'large-file-requires-review')); continue
        count+=1; found.extend(findings(name,data))
    return count,found

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--staged',action='store_true'); args=parser.parse_args()
    try: count,found=scan(args.staged)
    except (ValueError, subprocess.CalledProcessError): print('Preflight could not inspect the selected Git state.');sys.exit(2)
    for file,line,rule in found: print(f'{file}:{line}: {rule}')
    print(f'Checked {count} files; {len(found)} findings. Binary assets still require manual review.')
    sys.exit(bool(found))
