# Beyond Data Platform Helm Chart

## Configuration

Ensure the `KUBECONFIG` environment variable is pointing to a valid Kubernetes configuration file.

If you don't have a cluster available, one can be created using [this](https://github.com/bombeke/im-cluster) project.


## Installing CertManager
Add repository and install chart
```sh
helm repo add jetstack https://charts.jetstack.io --force-update
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.1 \
  --set crds.enabled=true
```
Deploy the certificate Issuer
```sh
helm install certmanagerissuer --namespace cert-manager dhis2/certmanager --set enabled=true
```

Add the annotations to Ingress
```
 annotations:
   cert-manager.io/cluster-issuer: "le-staging"
   ...
```

## Installing DHIS2 Core Helm

[DHIS2 core helm chart](./charts/core) is published to
https://bombeke.github.io/dhis2-helm

To install the chart you first need to add this chart repository

```sh
helm repo add dhis2 https://bombeke.github.io/dhis2-helm
helm repo update
helm search repo dhis2/core --versions
```
## Installing MongoDB
```sh
helm install psmdb-operator-crds percona/psmdb-operator-crds --namespace psmdb --create-namespace
helm install smart dhis2/smartai -n smart --create-namespace -f values.yaml

```
## Installing Dashboard
Apache Superset 6.1 (web, Celery worker and beat) with a bundled Valkey. The
metastore is an existing PostgreSQL database — for example the
[timescaledb chart](./charts/timescaledb) — whose database and role must exist
before install. Drivers for PostgreSQL/TimescaleDB (`psycopg2-binary`) and
ClickHouse (`clickhouse-connect`) are installed at pod start; see
[values.yaml](./charts/dashboard/values.yaml) for extensions, embedding,
alerts & reports, feature flags and the security settings.

Example dashboard.yaml
```yaml
metastore:
  host: timescaledb.data.svc.cluster.local
  # The timescaledb chart's ready-made connection URI, or set
  # username/database with password/existingSecret instead.
  uriSecret:
    name: timescaledb
    key: uri

ingress:
  enabled: true
  className: traefik
  certIssuer: le-prod
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
  hosts:
    - host: example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: example-com-tls
      hosts:
        - example.com

featureFlags:
  DASHBOARD_RBAC: true

# embedding:
#   enabled: true
#   allowedDomains:
#     - https://portal.example.com
# alerts:
#   enabled: true
#   smtp:
#     host: smtp.example.com
#     user: superset
#     existingSecret: superset-smtp
```
Install dashboard chart
```sh
    helm upgrade --install dashboard dhis2/dashboard --namespace dashboard --create-namespace -f dashboard.yaml
```
The admin password is generated on install; `helm status dashboard -n dashboard`
prints the command to read it.

## Installing the Iceberg REST Catalog
[Apache Gravitino's Iceberg REST catalog](./charts/gravitino), standalone. Table
definitions go in SQLite on a PVC (one replica) or in PostgreSQL (any number of
replicas). Data files go to MinIO or AWS S3, and `storage.provider` switches
between them. See the [chart README](./charts/gravitino/README.md) for switching,
IRSA, credential vending and tuning.

```sh
kubectl create secret generic lake-s3 -n lake \
  --from-literal=access-key=minioadmin --from-literal=secret-key='…'
helm upgrade --install catalog dhis2/gravitino -n lake --create-namespace \
  --set catalog.warehouse=s3://lake/warehouse \
  --set storage.endpoint=http://minio.minio.svc:9000 \
  --set storage.credentials.existingSecret=lake-s3
helm test catalog -n lake
```
Clients connect to `http://catalog-gravitino.lake.svc:9001/iceberg`. Keep the
`/iceberg` suffix.

## Installing SmartAI 
[DHIS2 smartai helm chart](./charts/smartai) is published to
https://bombeke.github.io/dhis2-helm

To update dhis2-helm chart repository

```sh
helm repo update
helm search repo dhis2/smartai --versions
helm install smart dhis2/smartai -n smart --create-namespace -f values.yaml
```
Example smart values.yaml

```yaml
origins:
 - "http://localhost:3000"
 - "localhost:3000"
 - "*"
dhis2:
 url: "https://dhis.example.com"
 username: "username"
 password: "password"
vector:
 dimension: 4096
broker:
 servers: "localhost:29092,localhost:39092,localhost:49092"
 password: "password"
 username: "username"
auth:
 auth_type: "casdoor"
 redirect_uri: "http://localhost:3000/#/auth-callback"
 real_name: "app-demo"
 server: "https://auth1.example.com"
 client_id: "94ce7d07f59820c8945f"
 client_secret: "354d4372aee1000b304a5991f75bfbfa12de6b59"
 org_name: "demo"
 application_name: "app-demo"
 certificate: "/opt/smartai/cert_public.pem"
api:
 server: "http://localhost:3000/#"
database:
 url: "localhost"
 password: "password"
smtp_settings:
  default:
    server: "smtp.example.com"
    port: 587
    username: "your_username@example.com"
    password: "your_password"
    use_tls: true
    timeout: 10
    
  gmail:
    server: "smtp.gmail.com"
    port: 587
    username: "your@gmail.com"
    password: "your_app_password"  # Use app password for Gmail
    use_tls: true
    timeout: 10
    
  no_tls_example:
    server: "mail.oldserver.com"
    port: 25
    username: "user@oldserver.com"
    password: "oldpassword"
    use_tls: false
    timeout: 10
```
## Installing AI/ML Inference Service
[AI/ML Inference server helm chart](./charts/tritonserver) is published to
https://bombeke.github.io/dhis2-helm

To update dhis2-helm chart repository

```sh
helm repo update
helm search repo dhis2/tritonserver --versions
```

## Installing Data Warehouse
```
starrocks:
    initPassword:
        enabled: true
        # Set a password secret, for example:
        # kubectl create secret generic starrocks-root-pass --from-literal=password='g()()dpa$$word'
        passwordSecret: starrocks-root-pass

    starrocksFESpec:
        replicas: 3
        service:
            type: LoadBalancer
        resources:
            requests:
                cpu: 1
                memory: 1Gi
        storageSpec:
            name: fe

    starrocksBeSpec:
        replicas: 3
        resources:
            requests:
                cpu: 1
                memory: 2Gi
        storageSpec:
            name: be
            storageSize: 15Gi

    starrocksFeProxySpec:
        enabled: true
        service:
            type: LoadBalancer
```
### Release a chart e.g core


The versions returned are gathered from [index.yaml](./index.yaml) which is
published to [this GitHub page](https://bombeke.github.io/dhis2-helm/index.yaml).

Bump the version in [Chart.yaml](./charts/core/Chart.yaml), commit and push.
**NOTE: do not create a tag yourself!**

Our release workflow will then using [Helm chart releaser action](https://github.com/helm/chart-releaser-action)

* create a tag `core-<version>`
* create a [release](https://github.com/bombeke/dhis2-helm/releases) associated with the new tag
* commit an updated index.yaml with the new release
* redeploy the GitHub pages to serve the new index.yaml

Note: there might be a slight delay between the release and the `index.yaml`
file being updated as GitHub pages have to be re-deployed.



### Drupal
$settings['trusted_host_patterns'] = array('^.*$');
