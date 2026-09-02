# RustDesk Server

[RustDesk Server](https://github.com/rustdesk/rustdesk-server) is the self-hosted backend for RustDesk, the open-source remote desktop application.

> **Status:** the chart templates are not implemented yet. The parameters below are the chart's values contract; `helm install` will not deploy anything until the templates land.

## TL;DR

```console
helm install my-release oci://ghcr.io/mohrezfadaei/charts/rustdesk-server
```

## Introduction

The chart deploys the two RustDesk Server OSS components as separate workloads:

- **`hbbs`** — ID / rendezvous server. Clients register here and it brokers direct connections via TCP hole punching.
- **`hbbr`** — relay server. Carries session traffic only when hole punching fails, which is the minority of sessions.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8.0+
- A way to expose UDP and TCP to clients — a `LoadBalancer` implementation, or `NodePort` with a widened port range. An HTTP Ingress cannot carry the UDP traffic `hbbs` needs.
- PV provisioner support, to persist the server key pair and peer database

## Installing the chart

```console
helm install my-release oci://ghcr.io/mohrezfadaei/charts/rustdesk-server
```

## Uninstalling the chart

```console
helm uninstall my-release
```

Persistent volumes are not removed by `helm uninstall`. Delete the PVCs manually if you want to discard the server key pair and peer database — note that a new key pair invalidates every already-configured client.

## Ports

| Port | Protocol | Component | Purpose |
| ---- | -------- | --------- | ------- |
| 21115 | TCP | `hbbs` | NAT type test |
| 21116 | TCP **and** UDP | `hbbs` | ID registration and heartbeat (UDP), hole punching (TCP) |
| 21117 | TCP | `hbbr` | Relay |
| 21118 | TCP | `hbbs` | WebSocket rendezvous, web client only |
| 21119 | TCP | `hbbr` | WebSocket relay, web client only |

Ports 21115–21117 are the minimum. Port 21114 is the Pro-only web console and has no effect in the OSS server.

## Configuration

### Connecting clients

Clients need two values, set under **Settings → Network**:

- **ID Server** — the external address of the `hbbs` service, e.g. `rustdesk.example.com` or `rustdesk.example.com:21116`
- **Key** — the server's public key

Leave **Relay Server** blank unless `hbbr` is reachable at a different address or port than `hbbs`; the client derives it otherwise.

### Providing the key pair

`hbbs` generates an `id_ed25519` / `id_ed25519.pub` pair in its working directory on first start, and clients must be configured with the matching public key. Because regenerating the pair invalidates every configured client, supply it explicitly in production:

```yaml
auth:
  existingSecret: rustdesk-keys
```

The Secret must hold the private key under `id_ed25519` and the public key under `id_ed25519.pub` (configurable via `auth.privateKeySecretKey` and `auth.publicKeySecretKey`).

Generate a pair with `rustdesk-utils`, which ships in the same image. The keys are base64-encoded raw Ed25519 keys, not OpenSSH-format keys, so `ssh-keygen` output will not work:

```console
docker run --rm docker.io/rustdesk/rustdesk-server:1.1.16 rustdesk-utils genkeypair
```

```console
kubectl create secret generic rustdesk-keys \
  --from-literal=id_ed25519=<secret key> \
  --from-literal=id_ed25519.pub=<public key>
```

By default the same pair is given to `hbbr` so it validates relay clients. Set `auth.relayKeyValidation=false` to keep upstream's default, where the relay accepts any client.

### Preserving the client source IP

Both servers derive peer addresses from the connection source, so they must see the real client IP. The chart defaults to `service.type=LoadBalancer` with `externalTrafficPolicy: Local` for this reason. If your cluster has no load balancer, `hbbs.hostNetwork=true` is the alternative.

### Setting the relay address

When `hbbr` is exposed on its own address — the usual case with one LoadBalancer per service — tell `hbbs` where it is:

```yaml
relayServers:
  - relay.example.com:21117
```

### Web client support

The WebSocket ports are disabled by default. `hbbs` and `hbbr` trust the `X-Real-IP` and `X-Forwarded-For` headers of WebSocket connections **without validating them**, so anyone who can reach ports 21118/21119 directly can forge a client IP and bypass IP-based limits. Only enable them behind a reverse proxy that sets `X-Real-IP` itself:

```yaml
hbbs:
  websocket:
    enabled: true
hbbr:
  websocket:
    enabled: true
```

### Forcing relayed connections

To disable direct connections entirely and route every session through `hbbr`:

```yaml
alwaysUseRelay: true
```

## Parameters

### Global parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `global.imageRegistry` | Global Docker image registry | `""` |
| `global.imagePullSecrets` | Global Docker registry secret names as an array | `[]` |
| `global.defaultStorageClass` | Global default StorageClass for Persistent Volume(s) | `""` |
| `global.compatibility.openshift.adaptSecurityContext` | Adapt the securityContext sections of the workloads to make them compatible with Openshift restricted-v2 SCC: remove runAsUser, runAsGroup and fsGroup and let the platform use their allowed default IDs. Possible values: auto (apply if the detected running cluster is Openshift), force (perform the adaptation always), disabled (do not perform adaptation) | `auto` |

### Common parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `kubeVersion` | Override Kubernetes version reported by .Capabilities | `""` |
| `nameOverride` | String to partially override common.names.name | `""` |
| `fullnameOverride` | String to fully override common.names.fullname | `""` |
| `namespaceOverride` | String to fully override common.names.namespace | `""` |
| `commonLabels` | Labels to add to all deployed objects | `{}` |
| `commonAnnotations` | Annotations to add to all deployed objects | `{}` |
| `clusterDomain` | Default Kubernetes cluster domain | `cluster.local` |
| `extraDeploy` | Array of extra objects to deploy with the release | `[]` |
| `diagnosticMode.enabled` | Enable diagnostic mode (all probes will be disabled and the command will be overridden) | `false` |
| `diagnosticMode.command` | Command to override all containers in the chart release | `["sleep"]` |
| `diagnosticMode.args` | Args to override all containers in the chart release | `["infinity"]` |

### RustDesk Server common parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `image.registry` | RustDesk Server image registry | `REGISTRY_NAME` |
| `image.repository` | RustDesk Server image repository | `REPOSITORY_NAME/rustdesk-server` |
| `image.digest` | RustDesk Server image digest in the way sha256:aa.... Please note this parameter, if set, will override the tag | `""` |
| `image.pullPolicy` | RustDesk Server image pull policy | `IfNotPresent` |
| `image.pullSecrets` | RustDesk Server image pull secrets | `[]` |
| `auth.existingSecret` | Name of an existing Secret containing the RustDesk key pair | `""` |
| `auth.publicKeySecretKey` | Key inside the existing Secret holding the public key | `id_ed25519.pub` |
| `auth.privateKeySecretKey` | Key inside the existing Secret holding the private key | `id_ed25519` |
| `auth.publicKey` | Contents of id_ed25519.pub, used when `auth.existingSecret` is not set | `""` |
| `auth.privateKey` | Contents of id_ed25519, used when `auth.existingSecret` is not set | `""` |
| `auth.annotations` | Additional custom annotations for the RustDesk key pair Secret | `{}` |
| `auth.relayKeyValidation` | Give hbbr the same key so it validates relay clients | `true` |
| `relayServers` | Relay addresses advertised to clients, as an array of `host` or `host:port` | `[]` |
| `alwaysUseRelay` | Force every session through the relay, disabling direct connections | `false` |
| `logLevel` | Log level for hbbs and hbbr (RUST_LOG) | `info` |

### hbbs (ID/rendezvous server) parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `hbbs.enabled` | Deploy the hbbs ID/rendezvous server | `true` |
| `hbbs.replicaCount` | Number of hbbs replicas to deploy | `1` |
| `hbbs.command` | Override default container command (useful when using custom images) | `[]` |
| `hbbs.args` | Override default container args (useful when using custom images) | `[]` |
| `hbbs.workingDir` | Working directory of the hbbs process | `/data` |
| `hbbs.containerPorts.nat` | hbbs NAT type test container port (PORT-1) | `21115` |
| `hbbs.containerPorts.main` | hbbs rendezvous container port, TCP and UDP (PORT) | `21116` |
| `hbbs.containerPorts.websocket` | hbbs WebSocket rendezvous container port (PORT+2) | `21118` |
| `hbbs.websocket.enabled` | Expose the WebSocket port used by the RustDesk web client | `false` |
| `hbbs.bind` | Local address hbbs binds all listeners to (BIND) | `""` |
| `hbbs.rmem` | UDP receive buffer size in bytes (RMEM), 0 uses the system default | `0` |
| `hbbs.testHbbs` | UDP self-test target checked at start-up (TEST_HBBS) | `""` |
| `hbbs.database.url` | Path of the SQLite database file (DB_URL) | `{{ .Values.hbbs.workingDir }}/db_v2.sqlite3` |
| `hbbs.database.maxConnections` | Size of the SQLite connection pool (MAX_DATABASE_CONNECTIONS) | `1` |
| `hbbs.extraEnvVars` | Array with extra environment variables to add to hbbs containers | `[]` |
| `hbbs.extraEnvVarsCM` | Name of existing ConfigMap containing extra env vars for hbbs containers | `""` |
| `hbbs.extraEnvVarsSecret` | Name of existing Secret containing extra env vars for hbbs containers | `""` |
| `hbbs.updateStrategy.type` | hbbs StatefulSet strategy type | `RollingUpdate` |
| `hbbs.podManagementPolicy` | Pod management policy for the hbbs StatefulSet | `OrderedReady` |
| `hbbs.revisionHistoryLimitCount` | Number of controller revisions to keep | `10` |
| `hbbs.statefulsetAnnotations` | Optionally add extra annotations on the hbbs StatefulSet resource | `{}` |
| `hbbs.automountServiceAccountToken` | Mount Service Account token in hbbs pods | `false` |
| `hbbs.hostAliases` | hbbs pod host aliases | `[]` |
| `hbbs.hostNetwork` | Run hbbs pods in the host network namespace | `false` |
| `hbbs.dnsPolicy` | DNS policy for hbbs pods | `""` |
| `hbbs.dnsConfig` | DNS configuration for hbbs pods | `{}` |
| `hbbs.podLabels` | Extra labels for hbbs pods | `{}` |
| `hbbs.podAnnotations` | Annotations for hbbs pods | `{}` |
| `hbbs.podAffinityPreset` | Pod affinity preset. Ignored if `hbbs.affinity` is set. Allowed values: `soft` or `hard` | `""` |
| `hbbs.podAntiAffinityPreset` | Pod anti-affinity preset. Ignored if `hbbs.affinity` is set. Allowed values: `soft` or `hard` | `soft` |
| `hbbs.nodeAffinityPreset.type` | Node affinity preset type. Ignored if `hbbs.affinity` is set. Allowed values: `soft` or `hard` | `""` |
| `hbbs.nodeAffinityPreset.key` | Node label key to match. Ignored if `hbbs.affinity` is set. | `""` |
| `hbbs.nodeAffinityPreset.values` | Node label values to match. Ignored if `hbbs.affinity` is set. | `[]` |
| `hbbs.affinity` | Affinity for hbbs pod assignment | `{}` |
| `hbbs.nodeSelector` | Node labels for hbbs pod assignment | `{}` |
| `hbbs.tolerations` | Tolerations for hbbs pod assignment | `[]` |
| `hbbs.topologySpreadConstraints` | Topology Spread Constraints for hbbs pod assignment | `[]` |
| `hbbs.priorityClassName` | hbbs pods' Priority Class Name | `""` |
| `hbbs.schedulerName` | Use an alternate scheduler, e.g. "stork". | `""` |
| `hbbs.terminationGracePeriodSeconds` | Seconds hbbs pods need to terminate gracefully | `""` |
| `hbbs.lifecycleHooks` | LifecycleHooks for the hbbs container to automate configuration before or after startup | `{}` |
| `hbbs.podSecurityContext.enabled` | Enabled hbbs pods' Security Context | `true` |
| `hbbs.podSecurityContext.fsGroupChangePolicy` | Set filesystem group change policy | `Always` |
| `hbbs.podSecurityContext.sysctls` | Set kernel settings using the sysctl interface | `[]` |
| `hbbs.podSecurityContext.supplementalGroups` | Set filesystem extra groups | `[]` |
| `hbbs.podSecurityContext.fsGroup` | Set hbbs pod's Security Context fsGroup | `1001` |
| `hbbs.containerSecurityContext.enabled` | Enabled hbbs container's Security Context | `true` |
| `hbbs.containerSecurityContext.seLinuxOptions` | Set SELinux options in container | `{}` |
| `hbbs.containerSecurityContext.runAsUser` | Set hbbs container's Security Context runAsUser | `1001` |
| `hbbs.containerSecurityContext.runAsGroup` | Set hbbs container's Security Context runAsGroup | `1001` |
| `hbbs.containerSecurityContext.runAsNonRoot` | Set hbbs container's Security Context runAsNonRoot | `true` |
| `hbbs.containerSecurityContext.readOnlyRootFilesystem` | Set hbbs container's Security Context readOnlyRootFilesystem | `true` |
| `hbbs.containerSecurityContext.privileged` | Set hbbs container's Security Context privileged | `false` |
| `hbbs.containerSecurityContext.allowPrivilegeEscalation` | Set hbbs container's Security Context allowPrivilegeEscalation | `false` |
| `hbbs.containerSecurityContext.capabilities.drop` | List of capabilities to be dropped | `["ALL"]` |
| `hbbs.containerSecurityContext.seccompProfile.type` | Set hbbs container's Security Context seccomp profile | `RuntimeDefault` |
| `hbbs.resourcesPreset` | Set hbbs container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). This is ignored if hbbs.resources is set. | `nano` |
| `hbbs.resources` | Set hbbs container requests and limits for different resources like CPU or memory | `{}` |
| `hbbs.livenessProbe.enabled` | Enable livenessProbe on hbbs containers | `true` |
| `hbbs.livenessProbe.initialDelaySeconds` | Initial delay seconds for livenessProbe | `20` |
| `hbbs.livenessProbe.periodSeconds` | Period seconds for livenessProbe | `10` |
| `hbbs.livenessProbe.timeoutSeconds` | Timeout seconds for livenessProbe | `5` |
| `hbbs.livenessProbe.failureThreshold` | Failure threshold for livenessProbe | `6` |
| `hbbs.livenessProbe.successThreshold` | Success threshold for livenessProbe | `1` |
| `hbbs.readinessProbe.enabled` | Enable readinessProbe on hbbs containers | `true` |
| `hbbs.readinessProbe.initialDelaySeconds` | Initial delay seconds for readinessProbe | `10` |
| `hbbs.readinessProbe.periodSeconds` | Period seconds for readinessProbe | `10` |
| `hbbs.readinessProbe.timeoutSeconds` | Timeout seconds for readinessProbe | `5` |
| `hbbs.readinessProbe.failureThreshold` | Failure threshold for readinessProbe | `6` |
| `hbbs.readinessProbe.successThreshold` | Success threshold for readinessProbe | `1` |
| `hbbs.startupProbe.enabled` | Enable startupProbe on hbbs containers | `false` |
| `hbbs.startupProbe.initialDelaySeconds` | Initial delay seconds for startupProbe | `10` |
| `hbbs.startupProbe.periodSeconds` | Period seconds for startupProbe | `10` |
| `hbbs.startupProbe.timeoutSeconds` | Timeout seconds for startupProbe | `5` |
| `hbbs.startupProbe.failureThreshold` | Failure threshold for startupProbe | `30` |
| `hbbs.startupProbe.successThreshold` | Success threshold for startupProbe | `1` |
| `hbbs.customLivenessProbe` | Custom livenessProbe that overrides the default one | `{}` |
| `hbbs.customReadinessProbe` | Custom readinessProbe that overrides the default one | `{}` |
| `hbbs.customStartupProbe` | Custom startupProbe that overrides the default one | `{}` |
| `hbbs.extraVolumes` | Optionally specify extra list of additional volumes for hbbs pods | `[]` |
| `hbbs.extraVolumeMounts` | Optionally specify extra list of additional volumeMounts for hbbs containers | `[]` |
| `hbbs.initContainers` | Add additional init containers to the hbbs pods | `[]` |
| `hbbs.sidecars` | Add additional sidecar containers to the hbbs pods | `[]` |
| `hbbs.persistence.enabled` | Enable persistence for hbbs using a PersistentVolumeClaim | `true` |
| `hbbs.persistence.existingClaim` | Name of an existing PVC to use for hbbs | `""` |
| `hbbs.persistence.storageClass` | PVC Storage Class for hbbs data volume | `""` |
| `hbbs.persistence.accessModes` | PVC Access Modes for hbbs data volume | `["ReadWriteOnce"]` |
| `hbbs.persistence.size` | PVC Storage Request for hbbs data volume | `1Gi` |
| `hbbs.persistence.annotations` | Annotations for the hbbs PVC | `{}` |
| `hbbs.persistence.labels` | Labels for the hbbs PVC | `{}` |
| `hbbs.persistence.selector` | Selector to match an existing Persistent Volume for hbbs data PVC | `{}` |
| `hbbs.service.type` | hbbs Kubernetes service type | `LoadBalancer` |
| `hbbs.service.ports.nat` | hbbs NAT type test service port | `21115` |
| `hbbs.service.ports.main` | hbbs rendezvous service port, exposed as both TCP and UDP | `21116` |
| `hbbs.service.ports.websocket` | hbbs WebSocket service port | `21118` |
| `hbbs.service.nodePorts.nat` | Node port for the NAT type test port | `""` |
| `hbbs.service.nodePorts.mainTCP` | Node port for the rendezvous TCP port | `""` |
| `hbbs.service.nodePorts.mainUDP` | Node port for the rendezvous UDP port | `""` |
| `hbbs.service.nodePorts.websocket` | Node port for the WebSocket port | `""` |
| `hbbs.service.extraPorts` | Extra ports to expose on the hbbs service | `[]` |
| `hbbs.service.clusterIP` | hbbs service Cluster IP | `""` |
| `hbbs.service.loadBalancerIP` | hbbs service Load Balancer IP | `""` |
| `hbbs.service.loadBalancerClass` | hbbs service Load Balancer class (optional, cloud specific) | `""` |
| `hbbs.service.loadBalancerSourceRanges` | Addresses that are allowed when the service is LoadBalancer | `[]` |
| `hbbs.service.externalTrafficPolicy` | Enable client source IP preservation for hbbs | `Local` |
| `hbbs.service.sessionAffinity` | Control where client requests go, to the same pod or round-robin | `None` |
| `hbbs.service.sessionAffinityConfig` | Additional settings for the sessionAffinity | `{}` |
| `hbbs.service.annotations` | Additional custom annotations for the hbbs service | `{}` |
| `hbbs.pdb.create` | Enable/disable a Pod Disruption Budget creation for hbbs | `true` |
| `hbbs.pdb.minAvailable` | Minimum number/percentage of hbbs pods that should remain scheduled | `""` |
| `hbbs.pdb.maxUnavailable` | Maximum number/percentage of hbbs pods that may be made unavailable. Defaults to `1` if both `hbbs.pdb.minAvailable` and `hbbs.pdb.maxUnavailable` are empty. | `""` |

### hbbr (relay server) parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `hbbr.enabled` | Deploy the hbbr relay server | `true` |
| `hbbr.replicaCount` | Number of hbbr replicas to deploy | `1` |
| `hbbr.command` | Override default container command (useful when using custom images) | `[]` |
| `hbbr.args` | Override default container args (useful when using custom images) | `[]` |
| `hbbr.workingDir` | Working directory of the hbbr process | `/data` |
| `hbbr.containerPorts.relay` | hbbr relay container port (PORT) | `21117` |
| `hbbr.containerPorts.websocket` | hbbr WebSocket relay container port (PORT+2) | `21119` |
| `hbbr.websocket.enabled` | Expose the WebSocket relay port used by the RustDesk web client | `false` |
| `hbbr.bind` | Local address hbbr binds its listeners to (BIND) | `""` |
| `hbbr.bandwidth.singleBandwidth` | Normal maximum bandwidth per relay connection, in Mb/s (SINGLE_BANDWIDTH) | `128` |
| `hbbr.bandwidth.totalBandwidth` | Aggregate bandwidth cap shared by all relay connections, in Mb/s (TOTAL_BANDWIDTH) | `1024` |
| `hbbr.bandwidth.limitSpeed` | Cap applied to downgraded connections and blacklisted IPs, in Mb/s (LIMIT_SPEED) | `32` |
| `hbbr.bandwidth.downgradeThreshold` | Fraction of singleBandwidth that triggers a downgrade, 0-1 (DOWNGRADE_THRESHOLD) | `0.66` |
| `hbbr.bandwidth.downgradeStartCheck` | Seconds before a connection becomes eligible for downgrade (DOWNGRADE_START_CHECK) | `1800` |
| `hbbr.blacklist` | IP addresses that hbbr limits to `hbbr.bandwidth.limitSpeed`, as an array | `[]` |
| `hbbr.blocklist` | IP addresses that hbbr refuses outright, as an array | `[]` |
| `hbbr.extraEnvVars` | Array with extra environment variables to add to hbbr containers | `[]` |
| `hbbr.extraEnvVarsCM` | Name of existing ConfigMap containing extra env vars for hbbr containers | `""` |
| `hbbr.extraEnvVarsSecret` | Name of existing Secret containing extra env vars for hbbr containers | `""` |
| `hbbr.updateStrategy.type` | hbbr StatefulSet strategy type | `RollingUpdate` |
| `hbbr.podManagementPolicy` | Pod management policy for the hbbr StatefulSet | `OrderedReady` |
| `hbbr.revisionHistoryLimitCount` | Number of controller revisions to keep | `10` |
| `hbbr.statefulsetAnnotations` | Optionally add extra annotations on the hbbr StatefulSet resource | `{}` |
| `hbbr.automountServiceAccountToken` | Mount Service Account token in hbbr pods | `false` |
| `hbbr.hostAliases` | hbbr pod host aliases | `[]` |
| `hbbr.hostNetwork` | Run hbbr pods in the host network namespace | `false` |
| `hbbr.dnsPolicy` | DNS policy for hbbr pods | `""` |
| `hbbr.dnsConfig` | DNS configuration for hbbr pods | `{}` |
| `hbbr.podLabels` | Extra labels for hbbr pods | `{}` |
| `hbbr.podAnnotations` | Annotations for hbbr pods | `{}` |
| `hbbr.podAffinityPreset` | Pod affinity preset. Ignored if `hbbr.affinity` is set. Allowed values: `soft` or `hard` | `""` |
| `hbbr.podAntiAffinityPreset` | Pod anti-affinity preset. Ignored if `hbbr.affinity` is set. Allowed values: `soft` or `hard` | `soft` |
| `hbbr.nodeAffinityPreset.type` | Node affinity preset type. Ignored if `hbbr.affinity` is set. Allowed values: `soft` or `hard` | `""` |
| `hbbr.nodeAffinityPreset.key` | Node label key to match. Ignored if `hbbr.affinity` is set. | `""` |
| `hbbr.nodeAffinityPreset.values` | Node label values to match. Ignored if `hbbr.affinity` is set. | `[]` |
| `hbbr.affinity` | Affinity for hbbr pod assignment | `{}` |
| `hbbr.nodeSelector` | Node labels for hbbr pod assignment | `{}` |
| `hbbr.tolerations` | Tolerations for hbbr pod assignment | `[]` |
| `hbbr.topologySpreadConstraints` | Topology Spread Constraints for hbbr pod assignment | `[]` |
| `hbbr.priorityClassName` | hbbr pods' Priority Class Name | `""` |
| `hbbr.schedulerName` | Use an alternate scheduler, e.g. "stork". | `""` |
| `hbbr.terminationGracePeriodSeconds` | Seconds hbbr pods need to terminate gracefully | `""` |
| `hbbr.lifecycleHooks` | LifecycleHooks for the hbbr container to automate configuration before or after startup | `{}` |
| `hbbr.podSecurityContext.enabled` | Enabled hbbr pods' Security Context | `true` |
| `hbbr.podSecurityContext.fsGroupChangePolicy` | Set filesystem group change policy | `Always` |
| `hbbr.podSecurityContext.sysctls` | Set kernel settings using the sysctl interface | `[]` |
| `hbbr.podSecurityContext.supplementalGroups` | Set filesystem extra groups | `[]` |
| `hbbr.podSecurityContext.fsGroup` | Set hbbr pod's Security Context fsGroup | `1001` |
| `hbbr.containerSecurityContext.enabled` | Enabled hbbr container's Security Context | `true` |
| `hbbr.containerSecurityContext.seLinuxOptions` | Set SELinux options in container | `{}` |
| `hbbr.containerSecurityContext.runAsUser` | Set hbbr container's Security Context runAsUser | `1001` |
| `hbbr.containerSecurityContext.runAsGroup` | Set hbbr container's Security Context runAsGroup | `1001` |
| `hbbr.containerSecurityContext.runAsNonRoot` | Set hbbr container's Security Context runAsNonRoot | `true` |
| `hbbr.containerSecurityContext.readOnlyRootFilesystem` | Set hbbr container's Security Context readOnlyRootFilesystem | `true` |
| `hbbr.containerSecurityContext.privileged` | Set hbbr container's Security Context privileged | `false` |
| `hbbr.containerSecurityContext.allowPrivilegeEscalation` | Set hbbr container's Security Context allowPrivilegeEscalation | `false` |
| `hbbr.containerSecurityContext.capabilities.drop` | List of capabilities to be dropped | `["ALL"]` |
| `hbbr.containerSecurityContext.seccompProfile.type` | Set hbbr container's Security Context seccomp profile | `RuntimeDefault` |
| `hbbr.resourcesPreset` | Set hbbr container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). This is ignored if hbbr.resources is set. | `nano` |
| `hbbr.resources` | Set hbbr container requests and limits for different resources like CPU or memory | `{}` |
| `hbbr.livenessProbe.enabled` | Enable livenessProbe on hbbr containers | `true` |
| `hbbr.livenessProbe.initialDelaySeconds` | Initial delay seconds for livenessProbe | `20` |
| `hbbr.livenessProbe.periodSeconds` | Period seconds for livenessProbe | `10` |
| `hbbr.livenessProbe.timeoutSeconds` | Timeout seconds for livenessProbe | `5` |
| `hbbr.livenessProbe.failureThreshold` | Failure threshold for livenessProbe | `6` |
| `hbbr.livenessProbe.successThreshold` | Success threshold for livenessProbe | `1` |
| `hbbr.readinessProbe.enabled` | Enable readinessProbe on hbbr containers | `true` |
| `hbbr.readinessProbe.initialDelaySeconds` | Initial delay seconds for readinessProbe | `10` |
| `hbbr.readinessProbe.periodSeconds` | Period seconds for readinessProbe | `10` |
| `hbbr.readinessProbe.timeoutSeconds` | Timeout seconds for readinessProbe | `5` |
| `hbbr.readinessProbe.failureThreshold` | Failure threshold for readinessProbe | `6` |
| `hbbr.readinessProbe.successThreshold` | Success threshold for readinessProbe | `1` |
| `hbbr.startupProbe.enabled` | Enable startupProbe on hbbr containers | `false` |
| `hbbr.startupProbe.initialDelaySeconds` | Initial delay seconds for startupProbe | `10` |
| `hbbr.startupProbe.periodSeconds` | Period seconds for startupProbe | `10` |
| `hbbr.startupProbe.timeoutSeconds` | Timeout seconds for startupProbe | `5` |
| `hbbr.startupProbe.failureThreshold` | Failure threshold for startupProbe | `30` |
| `hbbr.startupProbe.successThreshold` | Success threshold for startupProbe | `1` |
| `hbbr.customLivenessProbe` | Custom livenessProbe that overrides the default one | `{}` |
| `hbbr.customReadinessProbe` | Custom readinessProbe that overrides the default one | `{}` |
| `hbbr.customStartupProbe` | Custom startupProbe that overrides the default one | `{}` |
| `hbbr.extraVolumes` | Optionally specify extra list of additional volumes for hbbr pods | `[]` |
| `hbbr.extraVolumeMounts` | Optionally specify extra list of additional volumeMounts for hbbr containers | `[]` |
| `hbbr.initContainers` | Add additional init containers to the hbbr pods | `[]` |
| `hbbr.sidecars` | Add additional sidecar containers to the hbbr pods | `[]` |
| `hbbr.persistence.enabled` | Enable persistence for hbbr using a PersistentVolumeClaim | `false` |
| `hbbr.persistence.existingClaim` | Name of an existing PVC to use for hbbr | `""` |
| `hbbr.persistence.storageClass` | PVC Storage Class for hbbr data volume | `""` |
| `hbbr.persistence.accessModes` | PVC Access Modes for hbbr data volume | `["ReadWriteOnce"]` |
| `hbbr.persistence.size` | PVC Storage Request for hbbr data volume | `1Gi` |
| `hbbr.persistence.annotations` | Annotations for the hbbr PVC | `{}` |
| `hbbr.persistence.labels` | Labels for the hbbr PVC | `{}` |
| `hbbr.persistence.selector` | Selector to match an existing Persistent Volume for hbbr data PVC | `{}` |
| `hbbr.service.type` | hbbr Kubernetes service type | `LoadBalancer` |
| `hbbr.service.ports.relay` | hbbr relay service port | `21117` |
| `hbbr.service.ports.websocket` | hbbr WebSocket relay service port | `21119` |
| `hbbr.service.nodePorts.relay` | Node port for the relay port | `""` |
| `hbbr.service.nodePorts.websocket` | Node port for the WebSocket relay port | `""` |
| `hbbr.service.extraPorts` | Extra ports to expose on the hbbr service | `[]` |
| `hbbr.service.clusterIP` | hbbr service Cluster IP | `""` |
| `hbbr.service.loadBalancerIP` | hbbr service Load Balancer IP | `""` |
| `hbbr.service.loadBalancerClass` | hbbr service Load Balancer class (optional, cloud specific) | `""` |
| `hbbr.service.loadBalancerSourceRanges` | Addresses that are allowed when the service is LoadBalancer | `[]` |
| `hbbr.service.externalTrafficPolicy` | Enable client source IP preservation for hbbr | `Local` |
| `hbbr.service.sessionAffinity` | Control where client requests go, to the same pod or round-robin | `None` |
| `hbbr.service.sessionAffinityConfig` | Additional settings for the sessionAffinity | `{}` |
| `hbbr.service.annotations` | Additional custom annotations for the hbbr service | `{}` |
| `hbbr.pdb.create` | Enable/disable a Pod Disruption Budget creation for hbbr | `true` |
| `hbbr.pdb.minAvailable` | Minimum number/percentage of hbbr pods that should remain scheduled | `""` |
| `hbbr.pdb.maxUnavailable` | Maximum number/percentage of hbbr pods that may be made unavailable. Defaults to `1` if both `hbbr.pdb.minAvailable` and `hbbr.pdb.maxUnavailable` are empty. | `""` |

### Other parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `serviceAccount.create` | Specifies whether a ServiceAccount should be created | `true` |
| `serviceAccount.name` | The name of the ServiceAccount to use. If not set and create is true, a name is generated using the common.names.fullname template | `""` |
| `serviceAccount.annotations` | Additional Service Account annotations (evaluated as a template) | `{}` |
| `serviceAccount.labels` | Additional Service Account labels (evaluated as a template) | `{}` |
| `serviceAccount.automountServiceAccountToken` | Automount service account token for the ServiceAccount | `false` |
| `networkPolicy.enabled` | Specifies whether a NetworkPolicy should be created | `true` |
| `networkPolicy.allowExternal` | Don't require client label for connections | `true` |
| `networkPolicy.allowExternalEgress` | Allow the pods to access any range of ports and hosts | `true` |
| `networkPolicy.extraIngress` | Add extra ingress rules to the NetworkPolicy | `[]` |
| `networkPolicy.extraEgress` | Add extra egress rules to the NetworkPolicy | `[]` |
| `networkPolicy.ingressNSMatchLabels` | Labels to match to allow traffic from other namespaces | `{}` |
| `networkPolicy.ingressNSPodMatchLabels` | Pod labels to match to allow traffic from other namespaces | `{}` |


## Configuration examples

Specify each parameter with `--set`:

```console
helm install my-release \
  --set alwaysUseRelay=true \
  --set hbbs.persistence.size=2Gi \
  oci://ghcr.io/mohrezfadaei/charts/rustdesk-server
```

Or provide a YAML file:

```console
helm install my-release -f values.yaml oci://ghcr.io/mohrezfadaei/charts/rustdesk-server
```

### Fixed load balancer addresses with an existing key pair

```yaml
auth:
  existingSecret: rustdesk-keys

relayServers:
  - 203.0.113.20:21117

hbbs:
  service:
    loadBalancerIP: 203.0.113.10
  persistence:
    size: 2Gi

hbbr:
  service:
    loadBalancerIP: 203.0.113.20
```

### NodePort exposure

The default node port range is 30000–32767, so the API server must be started with `--service-node-port-range=21115-32767` for clients to reach the rendezvous port.

```yaml
hbbs:
  service:
    type: NodePort
    nodePorts:
      nat: 21115
      mainTCP: 21116
      mainUDP: 21116

hbbr:
  service:
    type: NodePort
    nodePorts:
      relay: 21117
```

### Tuning relay bandwidth

```yaml
hbbr:
  bandwidth:
    singleBandwidth: 256
    totalBandwidth: 2048
  resourcesPreset: medium
```

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](https://github.com/mohrezfadaei/rustdesk-server-helm/blob/main/LICENSE).
