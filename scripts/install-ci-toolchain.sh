#!/usr/bin/env bash
# Official rolling URLs are digest-locked. Upstream changes fail closed.
set -euo pipefail
root="${RUNNER_TEMP:?}/moonopenfeature-toolchain"
mkdir -p "$root/lib"
python3 - "$root" <<'PY'
import hashlib, json, pathlib, sys, urllib.request
lock = json.loads(pathlib.Path('scripts/toolchain-lock.json').read_text())
root = pathlib.Path(sys.argv[1])
for name in ['linux', 'core']:
    data = urllib.request.urlopen(lock[name + '_archive'], timeout=120).read()
    if hashlib.sha256(data).hexdigest() != lock[name + '_sha256']:
        raise SystemExit('Official ' + name + ' artifact changed; update the reviewed lock explicitly')
    (root / (name + '.tar.gz')).write_bytes(data)
PY
tar xzf "$root/linux.tar.gz" -C "$root"
tar xzf "$root/core.tar.gz" -C "$root/lib"
export MOON_HOME="$root" MOON_TOOLCHAIN_ROOT="$root"
export PATH="$root/bin:$PATH"
moon -C "$root/lib/core" bundle --all --warn-list '-a'
moon version --all
python3 - <<'PY'
import json, pathlib, subprocess
lock = json.loads(pathlib.Path('scripts/toolchain-lock.json').read_text())
actual = subprocess.check_output(['moon', 'version', '--all'], text=True)
for expected in [lock['moon'], lock['moonc']]:
    if expected not in actual:
        raise SystemExit('Toolchain version does not match reviewed lock')
PY
printf '%s
' "$root/bin" >> "$GITHUB_PATH"
printf 'MOON_HOME=%s
MOON_TOOLCHAIN_ROOT=%s
' "$root" "$root" >> "$GITHUB_ENV"
