# Verification status

- [x] Dedicated server UID, read-only release, private state, restricted network/CPU/memory.
- [x] Existing WG/SSH reused; pinned host; no new public route/firewall changes/autostart on Windows.
- [x] HMAC, roles, device binding, expiry, revocation, persistent replay nonces.
- [x] Unit tests: job lifecycle/idempotency/conflict, payload mutation, expiry, unregistered/cross-device request, cancel, lease loss, artifact traversal/hash/size, online backup/restore.
- [x] HTTP integration: authenticated status, unauthenticated/replayed requests rejected, oversized Content-Length rejected.
- [x] PowerShell 5.1 parser and lexical path tests.
- [x] Actual Windows -> existing SSH/WG forwarding -> Gateway: unauthenticated HTTP 403. Temporary forwarding process removed after test.
- [ ] Junction negative test: creation denied by Codex environment; owner-run test required.
- [ ] Full Windows install/uninstall, DPAPI enrollment and authenticated heartbeat: owner has not run installer.
- [ ] Actual tool versions, PNG, GLB, Godot import/headless result: pending owner agent execution.
- [ ] GPU/VRAM/CUDA/OptiX: not tested; CPU fixture only.
- [ ] ROBOT-REF-V1/V0.2 inventory and reviewed scripts: assets absent in canonical repository.
- [ ] Script/test/export handler integration, verified Git source packages, auto retention, descendant process Job Objects: pending; allowlists start empty, see architecture/threat model.

No production website configuration or existing game/source file was changed. Acceptance remains incomplete until unchecked mandatory items have evidence.
