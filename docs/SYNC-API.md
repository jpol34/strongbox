# Strongbox sync API

The BYOC (bring-your-own-cloud) HTTP contract implemented by `server/`, Strongbox's reference
sync server. This is a zero-knowledge store: it only ever holds ciphertext and non-secret
metadata (name, scope, project, version, device ID, timestamp). The encryption key is derived
from a passphrase that never leaves the client, so the server cannot read, and has no way to
recover, any secret's plaintext value.

The reference implementation is one Docker-packaged Pode server backed by SQLite, sized for
Pi/NAS-class hardware - not a specific hosted product, and no third-party vendor name appears in
this directory or its Dockerfile. Any server implementing this same contract is compatible with
Strongbox's sync client.

## TLS

Unlike Strongbox's local web UI (loopback-only, TLS optional/cosmetic), this server is designed
to be reached off-LAN. Plain HTTP is only acceptable for loopback or private-network testing.
Any real deployment requires TLS, either:

- via Pode's own HTTPS support (`-Certificate`/`-CertificatePassword` - point
  `STRONGBOX_SYNC_CERT_FILE`/`STRONGBOX_SYNC_CERT_PASSWORD` at a real certificate, not a
  self-signed one you trust yourself - that trick only works for the local UI because its client
  and server share a machine), or
- a reverse proxy terminating TLS in front of the container.

Every request past device registration carries a bearer token in the clear over the connection,
and `GET /secrets` returns device IDs and project names - both good reasons TLS is a real
requirement here, not a nice-to-have.

## Authentication

Two token tiers:

- **Admin bootstrap token** - generated server-side on first boot (32 random bytes, base64),
  written to a file inside the server's persistent data directory (never an environment variable,
  never a default baked into the Dockerfile or an example compose file), and printed once to the
  server's startup log. Only `POST /devices` accepts it.
- **Per-device bearer token** - issued by `POST /devices`, required by every other endpoint.
  Stored server-side as a hash, never in plaintext; validated with a constant-time comparison.

Send both as `Authorization: Bearer <token>`.

## Endpoints

### `POST /devices`

Registers a device and issues its bearer token. Requires the admin bootstrap token.

Request:
```json
{ "deviceName": "jordans-laptop" }
```

Response (`200`):
```json
{ "deviceId": "5b6c...", "token": "base64-device-token" }
```

`401` if the bootstrap token is missing or wrong.

### `POST /secrets/:name`

Pushes an envelope for one secret. Requires a device bearer token.

Request:
```json
{
  "scope": "global | project",
  "project": "repo-slug",
  "expectedVersion": 0,
  "salt": "base64",
  "nonce": "base64",
  "tag": "base64",
  "ciphertext": "base64"
}
```

`project` is required when `scope` is `"project"`, omitted for `"global"`. `expectedVersion` is
the version the client last saw for this `(name, scope, project)` - `0` for a secret that has
never been pushed.

Response (`200`):
```json
{ "name": "myapp.Api_Key", "version": 1 }
```

`409` if `expectedVersion` doesn't match the version currently stored - the stored value is left
untouched. The client should `GET` the current version, reconcile, and retry; this endpoint never
silently overwrites a version it wasn't told about.

### `GET /secrets/:name?scope=&project=`

Pulls one secret's envelope. `scope` defaults to `global`. Requires a device bearer token.

Response (`200`): same shape as a push body, plus `version`, `deviceId` (the last device to push
it), and `updatedAt`.

`404` if no matching secret exists.

### `GET /secrets`

Lists every stored secret's metadata - name, scope, project, version, `deviceId`, `updatedAt`.
Never returns `salt`/`nonce`/`tag`/`ciphertext`. Requires a device bearer token.

### `DELETE /secrets/:name?scope=&project=`

Deletes one secret's envelope. `scope` defaults to `global`. Requires a device bearer token.
`404` if it didn't exist.

## Running the reference server locally

```
cd server
docker compose up
```

No external dependency - SQLite lives on a named volume. The admin bootstrap token is printed to
the container's startup log and also written to `admin-bootstrap-token` inside that volume.

`Test-StrongboxSyncServer.ps1` in the same directory exercises every endpoint end-to-end via
`Invoke-RestMethod` against a running server:

```powershell
pwsh -File server/Test-StrongboxSyncServer.ps1 -BaseUrl http://127.0.0.1:8080 -BootstrapToken <token>
```
