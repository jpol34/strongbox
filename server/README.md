# Strongbox sync server (reference implementation)

A vendor-neutral, self-hostable reference server for Strongbox's opt-in cloud sync. Zero-knowledge:
it only ever stores/serves ciphertext plus non-secret metadata (name, scope, project, version,
device ID, timestamp) - the encryption key never leaves a client. See
[`../docs/SYNC-API.md`](../docs/SYNC-API.md) for the full HTTP contract.

Built with Pode (already a Strongbox dependency), backed by SQLite via the `PSSQLite` module -
sized for Pi/NAS-class hardware, no external database required.

## Run it

```
docker compose up
```

The admin bootstrap token is generated on first boot, printed once to the container's startup
log, and written to `admin-bootstrap-token` inside the persistent `strongbox-sync-data` volume.
Only `POST /devices` accepts it - every other endpoint needs a per-device bearer token issued by
that call.

Plain HTTP here is only for loopback/private-network testing - see docs/SYNC-API.md for the TLS
requirement before exposing this anywhere else.

## Verify it

```powershell
pwsh -File Test-StrongboxSyncServer.ps1 -BaseUrl http://127.0.0.1:8080 -BootstrapToken <token>
```

Exercises every endpoint (device registration, push/pull/list/delete, the stale-version 409) via
`Invoke-RestMethod`. There's no Pester coverage plan for this server, matching the existing gap
noted for the local UI - this script is the practical minimum instead of full unit coverage.

## Layout

- `Start-StrongboxSyncServer.ps1` - entry point (also the Dockerfile's `ENTRYPOINT`)
- `StrongboxSync.psm1` - imports everything under `Private/` as a real module, so its commands are
  visible inside Pode's route scriptblocks (Pode's runspace pool only inherits commands from
  imported modules and functions declared in the server scriptblock's own text, not from files
  dot-sourced at setup time)
- `Private/Storage/*.ps1` - the `Get-Blob`/`Put-Blob`/`Remove-Blob`/`Get-BlobMetadataList`
  interface, SQLite-backed - the one deliberate seam for swapping the store later
- `Private/*.ps1` - device registration/auth (bootstrap token, per-device token hashing and
  validation)
