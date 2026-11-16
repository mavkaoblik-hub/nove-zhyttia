# Protocol v1

Request headers: X-Principal, X-Time (Unix seconds), X-Nonce (32 lowercase hex), X-Signature. Signature = HMAC-SHA256(key, METHOD + LF + PATH + LF + TIME + LF + NONCE + LF + SHA256(raw body)). GET body is empty. JSON UTF-8 without BOM. Every retry uses a new nonce; job retry retains the same idempotency key and exact body. Different payload under same key is rejected.

POST /v1/jobs (owner): exact fields job_id, device_id, action, arguments, created_at, expires_at, requested_by, revision_sha (40 hex), idempotency_key, approval_required. Unix timestamps, maximum lifetime 24h. Creator forced to authenticated principal. No unregistered/revoked/expired device can receive new jobs.

POST /v1/heartbeat (device): version. POST /v1/lease: {} -> {job:null} or {job:{...},lease:opaque-token}. One active lease per device. POST /v1/jobs/ID/progress: {lease} -> state, extends 90s lease. POST /v1/jobs/ID/result: {lease,state,result}. GET /v1/jobs/ID: job,state,result,artifact metadata (owner or matching device). GET /v1/status owner only. POST /v1/jobs/ID/cancel owner only. Cancel stops at next local poll; do not interpret it as an instantaneous kill acknowledgement.

POST /v1/jobs/ID/artifacts: lease,name,sha256,content (base64). No filesystem path or arbitrary URL. 8 MiB/file and 256 MiB total quota. Immutable names within job. Retrieval for owner through existing vm_exec/SSH from /var/lib/mavka-game-bridge/artifacts/ID; verify returned SHA before viewing. No public download API.

State transitions: queued -> leased -> running -> succeeded/failed. Owner cancel -> cancelled. Queued job past expires_at -> expired. Lost active lease -> failed, manual reconciliation; no automatic replay. Sweeping occurs on API requests. Audit and immutable receipts preserve reconciliation evidence.

Action capability list is explicit in architecture.md. Unsupported actions return local failed result, never run a generic command. Local manual approval is independently enforced even if owner sets approval_required=false for a code-bearing action.

For future tool adapters: extend the same agent, typed parameters and local validators. Add positive/negative/cancel tests before enabling each action. No agent per program.
