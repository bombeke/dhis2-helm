# gravitino

Apache Gravitino's **Iceberg REST catalog**, standalone
(`apache/gravitino-iceberg-rest`). Writers commit tables into it; Trino, Spark
and DuckDB read them back. Data files go to S3 or MinIO. Table definitions go
to SQLite on a PVC or to PostgreSQL.

Clients connect to `http://<release>-gravitino.<ns>.svc:9001/iceberg`. Keep the
`/iceberg` suffix, because clients append `/v1/...` themselves. A bare
`/v1/config` returns 404, which is the same answer a wrong `uri` gets.

## What the chart fixes in the stock image

These were found by running `apache/gravitino-iceberg-rest:1.3.0`:

| Stock behaviour | Consequence | This chart |
| --- | --- | --- |
| `catalog-backend = memory`, `warehouse = /tmp` | Every table is lost on restart, and nothing is logged | Always uses a JDBC backend. It refuses to render unless `catalog.warehouse` is an `s3://` URI |
| Only one JDBC driver is included, and it is SQLite | Using PostgreSQL returns `400 Couldn't load jdbc driver` on the first call | Downloads the PostgreSQL jar, checks its sha256, and adds it to the classpath |
| The start script passes `-XX:-UseContainerSupport -Xmx1024m` | The heap ignores the pod's memory limit | Runs `java` directly with `MaxRAMPercentage` |
| `java` runs as a child of bash, and bash is PID 1 | SIGTERM is ignored. The pod is killed with SIGKILL when the grace period ends (a 15s timeout took 15.5s in testing) | `java` is PID 1. It shuts down cleanly in about 3s |
| `rewrite_config.py` rewrites `conf/` in place, and logs are written to `logs/` | A read-only root filesystem is not possible | The config is built in an emptyDir, and logs go to stdout |
| Secrets are passed as environment variables | They show up in `kubectl describe pod` and `/proc/1/environ` | Secrets are mounted as files and added to the config by an init container |

## Quick start (MinIO, SQLite)

```sh
kubectl create secret generic lake-s3 -n lake \
  --from-literal=access-key=minioadmin --from-literal=secret-key='…'

helm upgrade --install catalog dhis2/gravitino -n lake --create-namespace \
  --set catalog.warehouse=s3://lake/warehouse \
  --set storage.endpoint=http://minio.minio.svc:9000 \
  --set storage.credentials.existingSecret=lake-s3

helm test catalog -n lake   # creates, reads back and drops a namespace
```

The chart does not create the bucket, so create it first.

## Switching between MinIO and AWS S3

`storage.provider` controls the S3 settings that are easy to get wrong:

| | `minio` | `s3` |
| --- | --- | --- |
| `storage.endpoint` | **Required**, e.g. `http://minio.minio.svc:9000` | Leave empty for AWS. Set it only for a VPC or FIPS endpoint |
| Path-style access | **On**. MinIO puts the bucket in the path. Without this, every request goes to a `bucket.host` name and fails with a DNS error | **Off**. AWS uses virtual-hosted style |
| Credentials | Static keys | Static keys, **or** `defaultChain`: no keys, and IRSA, EKS Pod Identity or the instance profile supplies them |
| Credential vending | `s3-secret-key` | `s3-token` (STS, scoped to the table prefix) or `s3-secret-key` |

`storage.pathStyleAccess: true|false` overrides the derived value. Other
S3-compatible stores use `provider: minio`: Ceph RGW, Garage, SeaweedFS,
Cloudflare R2 and Wasabi.

### MinIO

```yaml
catalog:
  warehouse: s3://lake/warehouse
storage:
  provider: minio
  endpoint: http://minio.minio.svc:9000
  region: us-east-1            # MinIO ignores it, but the SDK requires one
  credentials:
    source: static
    existingSecret: lake-s3    # keys: access-key, secret-key
```

### AWS S3 with IRSA (no keys)

```yaml
catalog:
  warehouse: s3://acme-prod-lake/warehouse
storage:
  provider: s3
  endpoint: ""
  region: eu-west-1
  credentials:
    source: defaultChain
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/gravitino-catalog
```

The role needs `s3:GetObject`, `PutObject`, `DeleteObject` and `ListBucket` on
the warehouse prefix. On EKS Pod Identity, leave out the annotation and create
the association with `aws eks create-pod-identity-association`.

### AWS S3 with static keys

```yaml
storage:
  provider: s3
  endpoint: ""
  region: eu-west-1
  credentials:
    source: static
    existingSecret: lake-aws   # keys: access-key, secret-key
```

### What actually changes when you switch

- **Existing tables stay where they are.** Every Iceberg table stores the
  absolute `s3://bucket/...` path to its metadata and data files. Changing the
  provider or endpoint does not move them. To migrate from MinIO to S3, copy
  the bucket first, for example with `rclone sync minio:lake s3:acme-prod-lake`.
  If the bucket name changes, the paths inside the old metadata no longer
  match. In that case, re-register each table from its latest
  `metadata.json` (`POST /iceberg/v1/namespaces/{ns}/register`) after
  rewriting the paths.
- **`catalog.warehouse` only applies to new tables.** It sets the root for
  namespaces and tables created after the change.
- **Clients must switch too.** `GET /iceberg/v1/config` sends `s3.endpoint`,
  `s3.path-style-access` and `client.region` to clients as defaults. Most
  engines (Spark, PyIceberg) use them automatically. Trino does not: update
  its `s3.*` catalog properties yourself (see `NOTES.txt`). With credential
  vending on, clients also get their credentials from the catalog, so their
  keys do not need changing.

## Catalog backends

| | `sqlite` (default) | `postgresql` |
| --- | --- | --- |
| Replicas | 1 (enforced) | Any number |
| Upgrade strategy | `Recreate`, a few seconds of downtime | Rolling, `maxUnavailable: 0` |
| Durability | PVC with `helm.sh/resource-policy: keep` | Your database |
| Dependencies | None | A database, plus the driver jar |

SQLite runs in WAL mode with a `busy_timeout`. Both were checked on a running
pod. PostgreSQL with the [timescaledb chart](../timescaledb):

```yaml
catalog:
  backend: postgresql
  postgresql:
    host: timescaledb.data.svc.cluster.local
    database: gravitino
    username: gravitino
    existingSecret: timescaledb
    existingSecretPasswordKey: app-password
    params: sslmode=require&connectTimeout=10&socketTimeout=60&tcpKeepAlive=true
replicaCount: 2
```

In an air-gapped cluster, or with `networkPolicy.restrictEgress`, set
`catalog.postgresql.driver.download: false`. Then either build an image with
`postgresql-<ver>.jar` in `/opt/gravitino-iceberg-rest-server/libs`, or point
`driver.url` at an internal mirror.

## Security

- The pod runs as uid 1000 with a read-only root filesystem, all capabilities
  dropped, `RuntimeDefault` seccomp and no ServiceAccount token.
- Secrets are never environment variables. The assembled config is mode `0400`
  on a memory-backed emptyDir.
- **The catalog has no authentication by default.** Any pod that can reach it
  can drop every table. Either keep `networkPolicy.allowExternal: false` and
  list your engines in `networkPolicy.extraFrom`, or configure OAuth through
  `rawConfig` (`gravitino.authenticators: oauth`) and put the signing key in
  `extraSecretConfig`. Standalone mode supports authentication but not
  authorization.
- TLS: `tls.enabled` with a PKCS12 keystore. cert-manager can create one with
  `keystores.pkcs12.create: true`. Once enabled, the server accepts HTTPS
  only.
- `gravitino.fetchFile.blockUnsafeRemoteUri` (the SSRF guard) stays on.

## Performance

- **Memory:** heap = `jvm.maxRAMPercentage` (70%) of the memory limit, so the
  memory limit is the only setting to change. There is no CPU limit by
  default, because JVM startup is bursty and throttling it slows cold starts
  considerably. If you run without limits, set `jvm.activeProcessorCount` so
  GC threads are sized to your CPU request, not the node's core count.
- **Table metadata cache:** `table-metadata-cache-capacity` (default 2000)
  avoids reading `metadata.json` from object storage on every `loadTable`. It
  is keyed by metadata location, so it stays correct across replicas.
- **Jetty threads and queue:** `config.maxThreads` and
  `config.threadPoolWorkQueueSize`. Watch
  `iceberg_rest_server_http_server_*` at `/prometheus/metrics`
  (`metrics.serviceMonitor.enabled`).
- **DNS:** `-Dnetworkaddress.cache.ttl=60` lets the JVM pick up MinIO or
  database pods that are rescheduled to new IPs.

## Backups

The catalog is small, but losing it makes the lake unreadable. The Parquet
files survive, but nothing records which files make up which table.

- **SQLite:** take a VolumeSnapshot of `<release>-gravitino-data`. Alternatively,
  `kubectl exec` and copy `catalog.db`, `catalog.db-wal` and `catalog.db-shm`
  together.
- **PostgreSQL:** your database's normal backups cover it.
