#!/bin/bash
set -euo pipefail
src=/home/ubuntu/game-bridge-work-20261116
release=/opt/mavka-game-bridge/releases/1.0.0
test "$(id -u)" = 0
test ! -e /opt/mavka-game-bridge/current
test ! -e /etc/systemd/system/mavka-game-bridge.service
test ! -e "$release"
python3 -m unittest discover -s "$src/tests" -v
systemd-analyze verify "$src/deploy/mavka-game-bridge.service"
install -d -m 0700 /var/backups/mavka-game-bridge
systemctl list-units --type=service --state=running --no-legend --no-pager | awk '{print $1}' > /var/backups/mavka-game-bridge/pre-install-running.txt
if ! id mavka-game-bridge >/dev/null 2>&1; then useradd --system --home-dir /var/lib/mavka-game-bridge --shell /usr/sbin/nologin mavka-game-bridge; fi
install -d -m 0755 /opt/mavka-game-bridge /opt/mavka-game-bridge/releases "$release"
install -m 0644 "$src"/gateway/*.py "$release/"
install -d -m 0750 -o root -g mavka-game-bridge /etc/mavka-game-bridge
install -d -m 0700 -o mavka-game-bridge -g mavka-game-bridge /var/lib/mavka-game-bridge
python3 - <<'PY'
import os,json,secrets,time,grp
p='/etc/mavka-game-bridge/credentials.json'
with open(p,'x') as f:json.dump({'owner':{'role':'owner','key':secrets.token_hex(32),'expires_at':int(time.time())+30*86400}},f)
os.chmod(p,0o640);os.chown(p,0,grp.getgrnam('mavka-game-bridge').gr_gid)
PY
ln -s "$release" /opt/mavka-game-bridge/current
install -m 0644 "$src/deploy/mavka-game-bridge.service" /etc/systemd/system/mavka-game-bridge.service
systemctl daemon-reload
systemctl enable --now mavka-game-bridge
sleep 1
if ! python3 /opt/mavka-game-bridge/current/owner.py status; then
 systemctl disable --now mavka-game-bridge
 echo 'Health failed; bridge stopped, all state retained' >&2
 exit 1
fi
python3 /opt/mavka-game-bridge/current/owner.py backup
python3 - <<'PY'
import pathlib,subprocess
before=set(pathlib.Path('/var/backups/mavka-game-bridge/pre-install-running.txt').read_text().split())
after=set(subprocess.check_output(['systemctl','list-units','--type=service','--state=running','--no-legend','--no-pager'],text=True).splitlines())
after={x.split()[0] for x in after}
missing=before-after
print('Previously running services no longer running:',sorted(missing))
if missing:raise SystemExit(1)
PY
