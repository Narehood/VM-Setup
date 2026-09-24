#!/usr/bin/env python3
"""Apply VM-Setup's small hardening patch to the verified upstream UniFi script.

Usage: python3 tools/harden-unifi.py downloaded-unifi-10.6.106.sh
Output: Installers/UniFi-Controller.sh. Never executes the downloaded script.
"""
import hashlib
import re
import sys
from pathlib import Path

EXPECTED = '582e88b863419121aca8af0aaf769f4062fe5f8ff4c04328b0c17eddcfe3d664'
data = Path(sys.argv[1]).read_bytes()
if hashlib.sha256(data).hexdigest() != EXPECTED:
    raise SystemExit('Upstream checksum mismatch; review a new version before updating this tool.')
text = data.decode().replace('\r\n', '\n')
text = text.replace('#!/bin/bash\n', '#!/bin/bash\n# REQUIRES_ROOT: true\n# VM-Setup patches: tools/harden-unifi.py; upstream provenance: UPSTREAM.md\n', 1)
text, count = re.subn(r'^update_script\(\) \{.*?^\}', '''update_script() {
  echo 'VM-Setup pins this installer. Update VM-Setup to obtain a reviewed UniFi script.' >&2
  return 0
}''', text, count=1, flags=re.M | re.S)
assert count == 1
text, count = re.subn(r'^set_curl_arguments\(\) \{.*?^\}', '''set_curl_arguments() {
  locate_http_proxy
  # Never downgrade certificate verification for external downloads.
  curl_argument=(--fail --silent --show-error --retry 3 --connect-timeout 20 --max-time 600 --proto '=https' --proto-redir '=https')
  curl_argument+=("${curl_proxy_arg[@]}")
  nos_curl_argument=("${curl_argument[@]}")
}''', text, count=1, flags=re.M | re.S)
assert count == 1
text = text.replace('curl -ksS ', 'curl -fsS --connect-timeout 20 --max-time 60 ')
text = text.replace('"${curl_argument[@]}" --insecure', '"${curl_argument[@]}"')
for function in ('get_unifi_application_status', 'get_uos_server_status'):
    pattern = rf'^{function}\(\) \{{.*?^\}}'
    match = re.search(pattern, text, flags=re.M | re.S)
    assert match is not None
    block = match.group().replace('--insecure', '"${status_tls_args[@]}"')
    lines = block.splitlines()
    host_index = next(i for i, line in enumerate(lines) if 'local host=' in line)
    lines[host_index + 1:host_index + 1] = [
        '  local status_tls_args=(--connect-timeout 2 --max-time 6)',
        '  case "$host" in localhost|127.0.0.1|\'[::1]\') status_tls_args+=(--insecure) ;; esac',
    ]
    text = text[:match.start()] + '\n'.join(lines) + text[match.end():]
text = re.sub(r'rm --force "\$\{script_location\}" 2>/dev/null', ': # VM-Setup owns this file; retain it.', text)
# Repository keys must also use HTTPS, irrespective of the upstream mirror probe.
text = text.replace('${repo_http_https}://pgp.mongodb.com/', 'https://pgp.mongodb.com/')
Path(__file__).resolve().parents[1].joinpath('Installers/UniFi-Controller.sh').write_text(text, encoding='utf-8', newline='\n')
