# Work/Codex operator workflow

Use connected Oracle VM tool `vm_exec` with explicit cwd `/opt/mavka-game-bridge/current` and `as_root=true` for owner CLI. Existing SSH/VPN is the authority boundary. Chat alone does not control the PC. Owner must install and run start-bridge.ps1; no hidden autostart.

Replace REV below with reviewed source commit (40 hex). Until a source package exists, this labels the reviewed bridge revision; local staging manifest separately identifies game files.

```
python3 issue-job.py system.health --revision REV
python3 issue-job.py blender.version --revision REV
python3 issue-job.py godot.version --revision REV
python3 owner.py status
python3 owner.py get JOB_ID
python3 owner.py cancel JOB_ID
python3 issue-job.py workspace.stage_revision --revision REV
python3 issue-job.py blender.render --revision REV
python3 issue-job.py godot.project.import --revision REV --arguments '{"model_job_id":"RENDER_JOB_ID"}'
python3 issue-job.py godot.project.validate --revision REV
```

The last four require independent local approval. While agent displays Waiting for local approval, inspect receipt and run `powershell.exe -NoProfile -File "$env:LOCALAPPDATA\MaVkaGameBridge\approve.ps1" -JobId JOB_ID` in a second terminal. Never approve unreviewed project code. Exact receipt hash binds approval; approval timeout 5min. Agent runs CPU fixture only; no claims about ROBOT-REF-V1 or robot V0.2. “Render robot” remains unavailable until actual robot assets/scripts are inventoried and approved; do not substitute the fixture as a robot result.

“Validate godot” maps to staging headless editor --quit with real exit code/log. Dedicated game tests and export presets are not yet enabled. “Import model” accepts only smoke.glb from a prior local job. Stage before render/import; source is never overwritten. Inspect PNG/GLB/log and hashes, review diffs, then approve promotion manually. Promotion is not automated.

GitHub: canonical repo mavkaoblik-hub/nove-zhyttia, branch feat/game-bridge-v1. Connected tools create_tree -> create_commit -> update_ref -> draft PR, preserve existing main tree. No credentials, scene binaries, rendering outputs or local project data in Git. Code/docs only. Large assets remain private on Oracle under quotas; LFS not enabled without actual asset policy.
