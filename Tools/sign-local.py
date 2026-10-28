#!/usr/bin/env python3
# Copyright (C) 2026 dongx
# SPDX-License-Identifier: AGPL-3.0-only
"""Persistent project-local identity; never install a trusted root certificate."""
import hashlib, json, os, pathlib, secrets, shlex, shutil, subprocess, sys
root=pathlib.Path(__file__).resolve().parent.parent
folder=root/'.signing'
def run(*args, **kw):
    result=subprocess.run(args,capture_output=True,text=True,**kw)
    if result.returncode:
        print('Local signing operation failed:',result.stderr.strip(),file=sys.stderr)
        raise SystemExit(1)
    return result
if not (folder/'identity.json').exists():
    folder.mkdir(mode=0o700,exist_ok=True)
    password=secrets.token_urlsafe(24)
    (folder/'password').write_text(password);os.chmod(folder/'password',0o600)
    config='''[req]
distinguished_name=dn
[dn]
[v3]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
'''
    (folder/'openssl.cnf').write_text(config)
    openssl=shutil.which('openssl') or '/usr/bin/openssl'
    run(openssl,'req','-x509','-newkey','rsa:2048','-nodes','-sha256','-keyout',str(folder/'identity.key'),'-out',str(folder/'identity.crt'),'-days','3650','-subj','/CN=Shore Lyrics Local Signing/','-extensions','v3','-config',str(folder/'openssl.cnf'))
    os.chmod(folder/'identity.key',0o600)
    env=dict(os.environ,SHORE_CERT_PASSWORD=password)
    run(openssl,'pkcs12','-export','-inkey',str(folder/'identity.key'),'-in',str(folder/'identity.crt'),'-out',str(folder/'identity.p12'),'-passout','env:SHORE_CERT_PASSWORD','-certpbe','PBE-SHA1-3DES','-keypbe','PBE-SHA1-3DES','-macalg','sha1',env=env)
    os.chmod(folder/'identity.p12',0o600)
    search=shlex.split(run('security','list-keychains','-d','user').stdout)
    keychain=str(folder/'signing.keychain-db')
    try:
        if not pathlib.Path(keychain).exists():run('security','create-keychain','-p',password,keychain)
        run('security','set-keychain-settings','-lut','21600',keychain)
        run('security','unlock-keychain','-p',password,keychain)
        run('security','import',str(folder/'identity.p12'),'-k',keychain,'-P',password,'-T','/usr/bin/codesign')
        run('security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',password,keychain)
    finally:
        current=shlex.split(run('security','list-keychains','-d','user').stdout)
        if current!=search:run('security','list-keychains','-d','user','-s',*search)
    der=run(openssl,'x509','-in',str(folder/'identity.crt'),'-noout','-fingerprint','-sha1').stdout.split('=',1)[1].strip().replace(':','')
    (folder/'identity.json').write_text(json.dumps({'sha1':der}))
password=(folder/'password').read_text()
keychain=str(folder/'signing.keychain-db')
identity=json.loads((folder/'identity.json').read_text())['sha1']
run('security','unlock-keychain','-p',password,keychain)
try:
    result=run('codesign','--force','--timestamp=none','--sign',identity,'--keychain',keychain,sys.argv[1])
    run('codesign','--verify','--deep','--strict',sys.argv[1])
    print('Signed with persistent project-local identity')
except subprocess.CalledProcessError as error:
    # Never expose the keychain password from command arguments.
    print('Local signing failed:',error.stderr.strip(),file=sys.stderr)
    sys.exit(1)
