# Stage 0 — verified 2026-11-16

- Oracle: oracle-cloud-pc, ubuntu UID 1001, sudo available, aarch64; Python 3.14.4, Git 2.53.0; root disk 172 GiB free at inspection.
- caddy, cloudflared, wg-quick@wg0, mavka-sync-api, mavka-web, mavka-panel-web, mavka-auth-v2-1 active. Many other production units remain untouched.
- Caddy is loopback-bound, proxy to existing 6080 service. Cloudflared uses --token-file, no /etc/cloudflared/config.yml; managed routing not enumerated because unnecessary for private transport. Tokens were not printed/read.
- WG address 10.77.0.1/24, one allowed peer 10.77.0.2/32, recent handshake. Existing owner plugin uses Windows SSH over this VPN. No private keys read.
- No existing /opt/mavka-game-bridge or /var/lib/mavka-game-bridge at inspection. Port 18773 unused. nft input policy accept; WG-specific existing rule for 18772. Full rule inspection subsequently confirmed a terminal reject; direct Windows access to 18773 timed out. No firewall changes made; pinned SSH forwarding reuses existing port 22.
- /home/ubuntu/mavka-sync exists, reserved for its existing service, not used. /home/ubuntu/backups mode 0700 owned ubuntu; existing application-specific backups were not inspected or reused. No generic compatible game backup timer found. Dedicated SQLite online backup provided.
- Canonical GitHub repo mavkaoblik-hub/nove-zhyttia contains README and the matching game specification. Base 459e88a5150dfda07123f068f5056a0523e40b33. It contains no Godot project or robot assets. arudichik-source/mavka-game is a different Phaser RPG.
- Windows paths/versions in the supplied TZ remain owner-reported, pending diagnostics.ps1. Bundled Codex Git exists in this session; this does not establish Git availability in the owner's normal shell. Python WindowsApps entries do not establish a working Python runtime.
- Windows files, ROBOT-REF-V1, V0.2, project.godot and GPU VRAM have not been inspected. Agent must be installed/run by owner. CPU fixture selected until actual GPU test.

Stage 0 completed for available remote inventory; local diagnostics and actual tool/asset inventory pending owner execution. No infrastructure changed during inventory.
