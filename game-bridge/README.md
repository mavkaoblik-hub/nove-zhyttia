# MaVka Game Bridge

One extensible Windows application and a private Python/SQLite gateway for reviewed development jobs. Blender and Godot are typed handlers in the same agent. No general-purpose remote shell, Windows service or Windows autostart is installed.

Use the existing owner-controlled SSH/VPN transport. Examples are templates: configure your own project/tool paths and pinned SSH connection locally. Keep credentials, diagnostic output, job history, hardware inventory and deployment reports outside Git. Do not publish a gateway or weaken host-key verification.

The Windows installer verifies a separately delivered manifest SHA-256 and each package file, uses a dedicated expiring device credential protected with DPAPI, and creates a Desktop shortcut. Project access starts denied. Exact-job local approval is required for code-bearing actions. Source stays separate from versioned staging and outputs.

Gateway requires Python standard library and a dedicated unprivileged account. Review deploy/mavka-game-bridge.service and install-server.sh before deployment. Default example transport is a private WireGuard address with SSH forwarding; it is not a public HTTP endpoint. deploy/backup.py creates and verifies private snapshots without overwriting live state.

Tests: `python3 -m unittest discover -s tests -v`; on Windows `powershell.exe -NoProfile -File tests\test_agent.ps1`. A skipped junction test is not a pass. Review and test real application paths, drivers and project scripts on the target PC. Approved-script/export lists start empty. The bridge does not sandbox trusted Blender/GDScript code or guarantee full process-tree isolation.

Manual setup: run read-only diagnostics locally, verify the package's manifest hash through an independent trusted channel, run install-agent.ps1 -PackageSha256 HASH, then open the Desktop shortcut. No tokens or live configuration belong in this repository. Installer hashes must be rebuilt when any package file is changed.