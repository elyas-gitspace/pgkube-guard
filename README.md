# pgkube-guard

Automated PostgreSQL backups on Kubernetes, with nightly restore tests to prove your dumps actually work.

## How it works

| CronJob | Default schedule | What it does |
|---|---|---|
| `backup` | 02:00 | `pg_dump` your database, upload it to S3, keep the last N dumps, notify on failure |
| `restore-test` | 04:00 | download the latest dump, restore it into a throwaway Postgres inside the pod, run a check query, notify on failure |

The restore test never receives your database credentials: it cannot touch production.

## Requirements

- Kubernetes 1.27+ and Helm 3
- A Postgres reachable from the cluster (in-cluster, RDS, Cloud SQL, VM...)
- An S3-compatible bucket (AWS S3, MinIO...)
- A read-only Postgres user, e.g. `GRANT pg_read_all_data TO backup_user;`

## Quick start

```bash
# 1. Create your credentials
kubectl create namespace pgkube-guard
kubectl create secret generic postgres-credentials -n pgkube-guard \
  --from-literal=username=backup_user --from-literal=password='...'
kubectl create secret generic s3-backup-credentials -n pgkube-guard \
  --from-literal=AWS_ACCESS_KEY_ID='...' --from-literal=AWS_SECRET_ACCESS_KEY='...'
kubectl create secret generic s3-restore-credentials -n pgkube-guard \
  --from-literal=AWS_ACCESS_KEY_ID='...' --from-literal=AWS_SECRET_ACCESS_KEY='...'

# 2. Write your settings
cp examples/values.example.yaml my-values.yaml

# 3. Install
helm install my-backup ./charts/pgkube-guard -n pgkube-guard -f my-values.yaml
```

Run a backup right now instead of waiting for the schedule:

```bash
kubectl create job --from=cronjob/my-backup-pgkube-guard-backup manual-backup -n pgkube-guard
```

## Configuration

All settings live in [`values.yaml`](charts/pgkube-guard/values.yaml). The main ones:

| Key | Description |
|---|---|
| `postgres.host`, `postgres.database` | Source database (required) |
| `postgres.existingSecret` | Secret holding the Postgres username and password |
| `postgres.sslMode` | `require` for managed databases, `prefer` for a Postgres without TLS |
| `storage.s3.bucket`, `storage.s3.region` | Where dumps are stored (bucket required) |
| `storage.s3.endpoint` | Set it for MinIO or any S3-compatible storage |
| `storage.s3.backupCredentials` / `restoreCredentials` | Write and read-only S3 credentials |
| `backup.schedule`, `backup.retention` | When to back up, how many dumps to keep |
| `restoreTest.checkQuery` | Query run after restore, must return a number > 0 |
| `notifications.*` | Slack webhook and healthchecks.io-style pings |

Credentials can also be passed inline (`postgres.username`, `storage.s3.backupCredentials.accessKeyId`...), the chart then creates the Secrets. Existing Secrets are recommended.

## Roadmap

- [x] Raw Kubernetes manifests
- [x] Helm chart
- [ ] Release automation and ArtifactHub listing
- [ ] Operator with a `PostgresBackup` CRD
