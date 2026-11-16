# Rollback and recovery

Emergency stop on Windows: run stop-agent.ps1 (creates STOP; polling loop stops/kills current tool). Remove STOP only for an intentional restart. Oracle: `sudo systemctl stop mavka-game-bridge`; revoke device with `sudo python3 /opt/mavka-game-bridge/current/owner.py revoke novezhyttia-pc`.

Before update: stop accepting jobs, allow active job to finish/cancel, online SQLite backup: `sudo python3 /opt/mavka-game-bridge/current/owner.py backup`; verify the printed path with `owner.py verify-backup PATH`. Also copy artifacts and credentials to a root-only backup directory while service stopped. Credentials are secret and must never be placed in release/Git archives.

Restore database only while service stopped: preserve current state directory as a rollback copy, restore verified SQLite backup as queue.sqlite with mavka-game-bridge ownership/mode 0600, remove stale WAL/SHM only from the restored isolated copy, run integrity_check, switch state directory and start. Test suite verifies online backup -> separate restore -> integrity and job persistence. Production restore is not performed during deployment because no preexisting bridge data exists.

Release switch: /opt/mavka-game-bridge/current symlink selects immutable release. For later upgrades retain previous link, switch back and restart if health fails. Schema v1 has only additive initial migration; no downgrade needed. Initial deployment rollback: stop/disable only mavka-game-bridge, retain credentials/state/releases for review. No existing service configuration has to be reverted.

Windows updates: stop agent; preserve complete installation directory (includes DPAPI credential; same-user recovery only); install a new independently hashed release into a separate directory and carry approved configuration after review. No automated in-place updater. Uninstall removes local key; -RemoveData deletes only default LocalAppData directory after reparse checks. Revoke Oracle device separately. Installer registers no autostart entry/service/task.
