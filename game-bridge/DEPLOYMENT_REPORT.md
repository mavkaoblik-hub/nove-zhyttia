# Deployment report — 2026-11-16

## Stage 0

Oracle inventory performed read-only before changes. Matching canonical GitHub repository identified: mavkaoblik-hub/nove-zhyttia; main baseline 459e88a5150dfda07123f068f5056a0523e40b33. Existing unrelated Phaser game and MAVKA Sync not modified. Canonical repository has no game source, project.godot or robot assets. Windows diagnostics script prepared for owner execution; local asset/tool inventory remains pending.

## Stage 1

Dedicated mavka-game-bridge system user, private SQLite state, root-owned release and credentials, hardened systemd unit installed on Oracle. Gateway 1.0.0 listening only on 10.77.0.1:18773. Authenticated owner status succeeded; no devices enrolled and no real jobs submitted. Existing services comparison reported missing_previous_services=[]; caddy/cloudflared/WireGuard and named MAVKA services all active. Memory ~17 MiB, NRestarts=0 at inspection.

Initial startup health check failed because parent release directories inherited 0700. Deployment stopped/disabled only the new bridge. Parent permissions corrected to 0755, install script corrected, bridge restarted and authenticated health passed. No production service was restarted/reconfigured. SQLite online backup created in root-only /var/backups/mavka-game-bridge; integrity_check=ok.

Firewall full inspection and actual Windows test showed direct private port rejected. No firewall rule changed. Windows -> existing pinned SSH/WG forwarding -> Gateway test succeeded with unauthenticated HTTP 403. Temporary test forward terminated afterward. Selected runtime transport is short-lived SSH forwarding managed by the single Windows application. Caddy/Cloudflare/SSH/WG configuration unchanged.

One Windows program prepared: desktop shortcut installed only by owner's installer, WinForms window + tray, automatic connection on launch, Connect/Disconnect/Stop job, local exact-job approval, visible journal, per-project deny-by-default access controls and isolated staging namespaces. No Windows autostart or service. Close stops connection; app stays visible if shutdown has not yet completed. Agent enrollment/install/UI lifecycle have not been executed on the owner's behalf, respecting explicit local-owner action requirement.

## Stage 2

Prepared source snapshot SHA manifest, CPU PNG+GLB fixture, fixed scene inspector with autoexec disabled, exact-revision/hash local script allowlist, approved Godot headless tests/export presets, staging import/editor validation, integrity-checked artifacts. Script/preset lists start empty. Job cancel uses owner API or local UI; no remote shell. Local snapshots do not prove Git-tree equivalence. Actual PNG/GLB/tool codes, GPU verification and game assets remain pending owner-run agent. No claim of a completed Blender -> Godot cycle. V0.2 and ROBOT-REF-V1 not accessed or changed.

## Stage 3

Typed issue-job.py and owner.py, protocol and operator commands prepared; one extensible agent for future tools. GitHub changes kept under game-bridge/ on a feature branch, draft PR; main is not merged by this work. Final branch commit/PR details are delivered in the chat and RELEASE.json.

## Tests / limitations

Server suite includes 10 independent queue/security/recovery tests plus 1 HTTP integration test (earlier runs counted imported repetitions; final suite removes duplication). PowerShell 5.1: 17 parser, traversal and project-access checks pass; junction creation denied by execution environment, test explicitly skipped. Script encoding is UTF-8 BOM for PowerShell 5.1 Unicode paths; JSON read explicitly UTF-8. Full UI/tray/shortcut/DPAPI install/uninstall and real tool execution are unverified pending owner action.

Residual work: actual Windows acceptance; verified source package delivery/Git provenance; process-tree Job Object isolation, bounded stdout pumping, automatic retention/backup scheduling, approved robot script/assets, large-build policy and production rollback drill with actual job data. Quotas/restricted handlers/manual approval currently fail closed around unavailable inputs. Acceptance checklist intentionally remains incomplete.
