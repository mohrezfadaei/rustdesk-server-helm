---
layout: default
---

A Helm chart for deploying [RustDesk Server](https://github.com/rustdesk/rustdesk-server) — the
self-hosted backend for the RustDesk remote desktop application — on Kubernetes.

Latest chart version: **{{ site.chart_version }}**

## Add the repository

```console
helm repo add rustdesk {{ site.chart_repo_url }}
helm repo update
```

## Install

```console
helm install rustdesk rustdesk/rustdesk-server
```

## What gets deployed

Two independent workloads, because RustDesk Server is two separate binaries:

| Component | Role | Ports |
| --- | --- | --- |
| `hbbs` | ID / rendezvous server, brokers direct connections via hole punching | 21115/TCP, 21116/TCP **and** UDP, 21118/TCP (web client) |
| `hbbr` | Relay server, used only when hole punching fails | 21117/TCP, 21119/TCP (web client) |

Clients reach both from outside the cluster, and 21116/UDP cannot traverse an HTTP Ingress, so the
chart exposes them through `LoadBalancer` services with `externalTrafficPolicy: Local` to preserve
the client source IP.

## Documentation

- [Chart README and full values reference](https://github.com/mohrezfadaei/rustdesk-server-helm/blob/main/charts/rustdesk-server/README.md)
- [Source repository](https://github.com/mohrezfadaei/rustdesk-server-helm)
- [RustDesk self-hosting docs](https://rustdesk.com/docs/en/self-host/)
