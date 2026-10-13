# pgkube-guard

Automated PostgreSQL backups on Kubernetes, with nightly restore tests to prove your dumps actually work.

## How it works

| CronJob | When | What it does |
|---|---|---|
| `pg-backup` | 02:00 | `pg_dump` your database, upload it to S3, keep the last N dumps, notify on failure |
| `pg-restore-test` | 04:00 | download the latest dump, restore it into a throwaway Postgres inside the pod, run a check query, notify on failure |

The restore test never receives your database credentials: it cannot touch production.

## Requirements

- Kubernetes 1.27+
- A Postgres reachable from the cluster (in-cluster, RDS, Cloud SQL, VM...)
- An S3-compatible bucket (AWS S3, MinIO...)
- A read-only Postgres user, e.g. `GRANT pg_read_all_data TO backup_user;`

## Quick start

```bash
# 1. Fill in your credentials (gitignored)
cp examples/secrets.example.yaml secrets.yaml

# 2. Set your host, database, bucket and check query
$EDITOR k8s/configmap.yaml

# 3. Deploy
kubectl apply -k k8s/
kubectl apply -f secrets.yaml
```

Run a backup right now instead of waiting for 02:00:

```bash
kubectl create job --from=cronjob/pg-backup manual-backup -n pgkube-guard
```

## Configuration

| Key (`k8s/configmap.yaml`) | Description |
|---|---|
| `PGHOST`, `PGPORT`, `PGDATABASE` | Source database |
| `PGSSLMODE` | `require` for managed databases, `prefer` for a Postgres without TLS |
| `S3_BUCKET`, `S3_PREFIX`, `AWS_DEFAULT_REGION` | Where dumps are stored |
| `AWS_ENDPOINT_URL` | Set it for MinIO or any S3-compatible storage |
| `RETENTION` | Number of dumps to keep |
| `CHECK_QUERY` | Query run after restore, must return a number > 0 |
| `NOTIFY_ON_SUCCESS` | Also send a Slack message when everything is fine |

Notifications (Slack webhook, healthchecks.io-style pings) are configured in the `notifications` Secret.

## Roadmap

- [x] Raw Kubernetes manifests
- [ ] Helm chart
- [ ] Release automation and ArtifactHub listing
- [ ] Operator with a `PostgresBackup` CRD
