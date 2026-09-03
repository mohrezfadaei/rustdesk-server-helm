<div align="center">

<img src="https://raw.githubusercontent.com/mohrezfadaei/rustdesk-server-helm/main/assets/icon.png" alt="RustDesk" width="128">

# RustDesk Server Helm

A production-ready, open-source Helm chart for deploying RustDesk server components on Kubernetes.

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/rustdesk-server-helm)](https://artifacthub.io/packages/search?repo=rustdesk-server-helm)
[![Lint](https://github.com/mohrezfadaei/rustdesk-server-helm/actions/workflows/lint.yaml/badge.svg)](https://github.com/mohrezfadaei/rustdesk-server-helm/actions/workflows/lint.yaml)
[![Security](https://github.com/mohrezfadaei/rustdesk-server-helm/actions/workflows/security.yaml/badge.svg)](https://github.com/mohrezfadaei/rustdesk-server-helm/actions/workflows/security.yaml)
[![License](https://img.shields.io/github/license/mohrezfadaei/rustdesk-server-helm)](LICENSE)

</div>

## Quick start

```console
helm repo add rustdesk https://mohrezfadaei.github.io/rustdesk-server-helm
helm repo update
helm install rustdesk rustdesk/rustdesk-server
```

## What gets deployed

[RustDesk Server](https://github.com/rustdesk/rustdesk-server) OSS is two independent binaries, so
the chart deploys them as two separate workloads:

| Component | Role | Ports |
| --- | --- | --- |
| `hbbs` | ID / rendezvous server. Clients register here and it brokers direct connections via TCP hole punching. | 21115/TCP, 21116/TCP **and** UDP, 21118/TCP (web client) |
| `hbbr` | Relay server. Carries session traffic only when hole punching fails. | 21117/TCP, 21119/TCP (web client) |

Each gets its own StatefulSet, Service, PodDisruptionBudget and NetworkPolicy, with persistence and
resources configured independently under the `hbbs:` and `hbbr:` value keys.

## Things worth knowing before you install

- **The key pair is the critical state.** `hbbs` generates `id_ed25519` / `id_ed25519.pub` on first
  start, and clients are configured with the matching public key. Regenerating it disconnects every
  configured client, so supply your own via `auth.existingSecret` in production.
- **UDP 21116 must reach the pod.** An HTTP Ingress cannot carry it, which is why the chart defaults
  to `LoadBalancer` services with `externalTrafficPolicy: Local` — both servers derive peer
  addresses from the connection source and need the real client IP.
- **The web client ports are off by default.** `hbbs` and `hbbr` trust the `X-Real-IP` and
  `X-Forwarded-For` headers of WebSocket connections without validating them, so 21118/21119 should
  only be exposed behind a reverse proxy that sets those headers itself.

## Documentation

- [Chart README](charts/rustdesk-server/README.md) — installation, configuration and the full values reference
- [Artifact Hub package](https://artifacthub.io/packages/search?repo=rustdesk-server-helm)
- [RustDesk self-hosting docs](https://rustdesk.com/docs/en/self-host/)

## Repository layout

```text
charts/rustdesk-server/   the chart itself
.github/workflows/        lint, security scan and release pipelines
.github/pages/            landing page and Artifact Hub metadata published to gh-pages
```

## Releasing

Pushing a tag in `MAJOR.MINOR.PATCH` form runs the release workflow, which syncs `Chart.yaml` to the
tag, packages the chart, and publishes it to the `gh-pages` Helm repository.

```console
git tag 0.1.0 && git push origin 0.1.0
```

## Contributing

Issues and pull requests are welcome. `helm lint` and a Trivy misconfiguration scan run on every
push, so please make sure both pass locally:

```console
helm lint charts/rustdesk-server --strict
helm template rustdesk charts/rustdesk-server
```

## License

Licensed under the [Apache License 2.0](LICENSE).
