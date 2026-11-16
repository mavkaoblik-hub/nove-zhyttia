# Architecture — 1.0.0

Codex -> existing Oracle VM plugin (SSH over WireGuard) -> owner.py -> private Gateway -> outbound polling Windows Agent -> approved tool -> bounded artifacts.

Canonical repository: mavkaoblik-hub/nove-zhyttia. Separate game-bridge/ directory and branch; never MAVKA-SYNC-SERVER. Base main commit: 459e88a5150dfda07123f068f5056a0523e40b33.

Gateway: Python standard library, SQLite WAL/schema version 1 (DDL in gateway/bridge.py), dedicated unprivileged account. Listen only 10.77.0.1:18773; application and systemd restrict source to inventoried peer 10.77.0.2 and VM itself. WireGuard provides encryption/authenticated transport; HMAC provides separate application identity and request integrity. HTTP here must never be exposed outside WireGuard. No Caddy, Cloudflare, firewall, SSH or WG configuration changes. Existing firewall rejects direct Windows access to 18773; start-bridge.ps1 uses pinned SSH over WireGuard, forwarding local 127.0.0.1:18774 to VM 10.77.0.1:18773. Agent connects only to this loopback endpoint.

Agent: PowerShell 5.1/.NET, foreground visible state, named mutex, one child tool, DPAPI credential. No autostart. Source, staging by revision, output by job ID, receipts, approvals separated. Local staging records file hashes; a supplied Git SHA labels provenance and does NOT certify that local files match that Git tree. Strict Git package delivery and promotion to source are not enabled.

Lease 90 seconds, renewed every 10 seconds during tool execution; expiry yields failed/manual reconciliation, never automatic re-execution. Owner retries with a new ID after inspecting output. Local immutable receipt also prevents replay. Cancel polled while tool runs; network loss stops execution on failed renewal.

Implemented automatic actions: health, tool versions, workspace status. Locally approved: staging snapshot, fixture render/GLB, fixed scene inspection, Godot inspect/import/editor validation and selected prior-output artifact upload. Exact-revision/hash scripts and Godot headless tests require a local reviewed script allowlist; export requires local preset allowlist. Both are empty by default. Job cancellation is implemented through owner HTTP API and local UI, not a queued job.cancel handler. No robot asset modification or source promotion.

One extensible Windows Agent serves every development tool. Add reviewed typed action handlers to the same program; do not install a separate agent or daemon per tool.
