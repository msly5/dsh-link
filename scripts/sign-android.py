#!/usr/bin/env python3
"""Sign an Android release APK on macOS using signing material stored in Keychain.

Requires JDK 17 (JAVA_HOME), Android SDK (ANDROID_HOME), and Xcode command-line tools.
Use --create-key only for the first release. Later updates must reuse the same key.
Private keys/passwords are never stored in the repository or passed in arguments.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('input', type=Path)
p.add_argument('output', type=Path)
p.add_argument('--create-key', action='store_true')
a = p.parse_args()
if sys.platform != 'darwin': raise SystemExit('This helper uses macOS Keychain. On other hosts use your own secure Android signing workflow.')
if not a.input.is_file() or a.output.exists(): raise SystemExit('Input must exist and output must not already exist.')
sdk = Path(os.environ.get('ANDROID_HOME', Path.home()/'Library/Android/sdk'))
tools = sdk/'build-tools'/'35.0.0'
java = Path(os.environ['JAVA_HOME'])/'bin'
if not (tools/'apksigner').is_file(): raise SystemExit('Install Android Build Tools 35.0.0.')
a.output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='dsh-android-sign-') as tmp:
    directory=Path(tmp);directory.chmod(0o700)
    cache=Path.home()/'.config/dsh-remote/cache'
    cache.mkdir(parents=True,exist_ok=True,mode=0o700)
    helper=cache/'android-keychain'
    source=ROOT/'scripts/android-keychain.swift'
    if not helper.exists() or helper.stat().st_mtime < source.stat().st_mtime:
        subprocess.run(['xcrun','swiftc',str(source),'-o',str(helper)],check=True,stdout=subprocess.DEVNULL)
        helper.chmod(0o700)
    result=subprocess.run([str(helper),'read'],capture_output=True)
    keyfile=directory/'release.p12'
    if result.returncode == 3:
        if not a.create_key: raise SystemExit('No release key in Keychain. Use --create-key for the first release only.')
        password=secrets.token_urlsafe(48)
        env={**os.environ,'DSH_ANDROID_SIGN_PASSWORD':password}
        subprocess.run([str(java/'keytool'),'-genkeypair','-keystore',str(keyfile),'-storetype','PKCS12','-alias','dsh-link',
                        '-keyalg','RSA','-keysize','3072','-validity','10000','-dname','CN=dsh link, O=dsh link',
                        '-storepass:env','DSH_ANDROID_SIGN_PASSWORD','-keypass:env','DSH_ANDROID_SIGN_PASSWORD'],env=env,check=True,capture_output=True)
        record={'password':password,'pkcs12':base64.b64encode(keyfile.read_bytes()).decode()}
        subprocess.run([str(helper),'create'],input=json.dumps(record).encode(),check=True,capture_output=True)
    elif result.returncode == 0:
        record=json.loads(result.stdout)
        password=record['password'];keyfile.write_bytes(base64.b64decode(record['pkcs12']))
        env={**os.environ,'DSH_ANDROID_SIGN_PASSWORD':password}
    else: raise SystemExit('Could not access the release signing key in macOS Keychain.')
    keyfile.chmod(0o600)
    aligned=directory/'aligned.apk'
    subprocess.run([str(tools/'zipalign'),'-P','16','4',str(a.input.resolve()),str(aligned)],check=True,capture_output=True)
    subprocess.run([str(tools/'apksigner'),'sign','--ks',str(keyfile),'--ks-key-alias','dsh-link',
                    '--ks-pass','env:DSH_ANDROID_SIGN_PASSWORD','--key-pass','env:DSH_ANDROID_SIGN_PASSWORD',
                    '--out',str(a.output.resolve()),str(aligned)],env=env,check=True,capture_output=True)
print('Signed release APK created. Signing material is retained in macOS Keychain.')
