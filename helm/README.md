# smb-test-server Helm chart

Runs the SMB Test Server container in Kubernetes. The test files are baked into
the image, so there is no PersistentVolume, no bind mount and nothing to seed —
a fresh pod always serves the same known file set.

## Install

The image must be reachable by the cluster first. `docker compose build`
produces `smb-test-server:local`, which only exists in the local Docker daemon,
so either push it to a registry or side-load it:

```bash
kind load docker-image smb-test-server:local
```

```bash
minikube image load smb-test-server:local
```

Then:

```bash
helm install smb ./helm -n smb-test --create-namespace
```

With a registry image:

```bash
helm install smb ./helm -n smb-test --create-namespace \
    --set image.repository=registry.example.com/smb-test-server \
    --set image.tag=0.1.0
```

## Test

`helm test` runs the repo README's verification steps from inside the cluster.
Three of the checks assert that something is **refused** — anonymous
enumeration, an unknown user, and writes — so a green run is evidence the share
is locked down, not just reachable:

```bash
helm test smb -n smb-test --logs
```

The write and delete checks assert on what the share actually holds afterwards
rather than on `smbclient`'s exit code, which can report success even when the
server refused the operation.

## Connect

`service.type` is `ClusterIP` by default, which is not reachable from outside
the cluster:

```bash
kubectl port-forward -n smb-test svc/smb-smb-test-server 1445:445
smbclient //localhost/testshare -p 1445 -U testuser
```

For clients outside the cluster, use `NodePort` or `LoadBalancer`. Note that
the Windows SMB *client* can only dial port 445, so a Windows client needs
`service.port: 445` and a path to it that does not remap the port — a
`NodePort` in the 30000s will not work for Windows.

## Values

The ones worth knowing about; see [values.yaml](values.yaml) for the rest, which
carries the reasoning inline.

| Key | Default | Notes |
| --- | --- | --- |
| `image.repository` / `image.tag` | `smb-test-server` / `local` | `local` only exists in a local Docker daemon. |
| `replicaCount` | `1` | Leave it. `smbd` holds session state in the pod, so a second replica behind one Service drops clients mid-session. |
| `auth.user` / `auth.password` | `testuser` / `testpass` | Guest access is always refused, so these are the only working credentials. |
| `auth.existingSecret` | `""` | Name of a Secret with an `smb-password` key, to keep the password out of values. |
| `smb.shareName` | `testshare` | |
| `smb.port` | `445` | Port `smbd` binds in the pod. Accepts a space-separated list, e.g. `"445 1445"`. |
| `smb.minProtocol` / `smb.maxProtocol` | `SMB2` / `SMB3` | Set both the same to pin one dialect. `NT1` for SMB1 clients, which also needs `smb.ntlmAuth: yes`. |
| `smb.logLevel` | `1` | `3` gives per-request protocol detail in `kubectl logs`. |
| `service.type` / `service.port` | `ClusterIP` / `445` | |

The password is applied by the container entrypoint at startup, so changing it
needs a pod restart. The Deployment carries a checksum annotation over the
Secret, which makes `helm upgrade` roll the pod automatically.

## What this chart deliberately does not do

**Run as non-root.** `smbd` runs as uid 0 here. Port 445 is privileged, and the
entrypoint renders `/etc/samba/smb.conf` and writes the `tdbsam` passdb under
`/var/lib/samba/private` at startup. Setting `runAsNonRoot: true` or
`readOnlyRootFilesystem: true` will crashloop the pod.

**Drop capabilities.** `capabilities.drop: [ALL]` also crashloops it: `smbd`
calls `setuid()`/`setgid()` to impersonate the authenticated user on every file
access, so it needs `CAP_SETUID`/`CAP_SETGID`, plus `CAP_NET_BIND_SERVICE` for
port 445. The default set is left intact, which matches how `docker-compose`
runs the same image. `allowPrivilegeEscalation: false` is set, and is safe.

**Change what is in the share.** That is decided at `docker build` time by the
`FIXTURE_*` build args (see the repo README). Rebuild and push a new tag.

This is a test fixture, not a hardened file server. Credentials are plaintext
in `values.yaml` unless you use `auth.existingSecret`, and a Kubernetes Secret
is encoding rather than encryption. Do not expose it publicly.
