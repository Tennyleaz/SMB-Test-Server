# SMB Test Server

A minimal containerised Samba server for exercising SMB **client** implementations.

- One named user, guest access refused outright
- Share is read-only through three independent layers
- Port, credentials, share name and protocol range are all configurable
- Logs go to `docker logs`, so auth failures are visible live

## Layout

```
Dockerfile
docker-compose.yml
.env.example            copy to .env
.gitattributes          forces LF - do not delete
config/smb.conf.tmpl    edit this, not the rendered smb.conf
scripts/entrypoint.sh
share/                  test files, bind-mounted read-only at /share
```

## Run

```sh
cp .env.example .env        # optional, defaults are baked in
docker compose up -d --build
docker compose logs -f
```

Default credentials: `testuser` / `testpass`, share `testshare`.

## Connect

Linux:

```sh
sudo mount -t cifs //<host>/testshare /mnt/smbtest \
    -o user=testuser,pass=testpass,port=445,vers=3.0,ro
```

macOS: `open 'smb://testuser@<host>/testshare'`

Windows: `net use Z: \\<host>\testshare /user:testuser testpass`

## Verification

```sh
# 1. share is listed with valid credentials
docker exec smb-test smbclient -L localhost -U testuser%testpass

# 2. anonymous enumeration must FAIL (restrict anonymous = 2, map to guest = Never)
docker exec smb-test smbclient -L localhost -N

# 3. bogus user must FAIL rather than fall back to guest
docker exec smb-test smbclient //localhost/testshare -U nobody%wrong -c 'ls'

# 4. read works
docker exec smb-test smbclient //localhost/testshare -U testuser%testpass \
    -c 'ls; get readme.txt /tmp/x'

# 5. write must FAIL
docker exec smb-test smbclient //localhost/testshare -U testuser%testpass \
    -c 'put /etc/hostname nope.txt'
```

Steps 2, 3 and 5 failing is the pass condition.

## Configuration

Everything lives in `.env`; see `.env.example` for the full list. The two most
useful knobs:

| Variable | Purpose |
| --- | --- |
| `SMB_HOST_PORT` | Port published on the host. What clients dial. |
| `SMB_PORT` | Port `smbd` binds inside the container. Matters with `--network host`, or to test non-standard-port handling. Accepts `"445 1445"`. |
| `SMB_MIN_PROTOCOL` / `SMB_MAX_PROTOCOL` | Pin the dialect range, e.g. both `SMB2_02` to force an old dialect. |
| `SMB_LOG_LEVEL` | Raise to `3` for per-request protocol detail. |

To test a legacy SMB1 client, set `SMB_MIN_PROTOCOL=NT1` and, if auth then
fails, `SMB_NTLM_AUTH=yes`. Leave both at their defaults otherwise.

## Gotchas

**Port 445 on a Windows host.** Windows reserves 445 for its own
`lanmanserver`, so `445:445` will not bind. Set `SMB_HOST_PORT=1445`. Be aware
the Windows SMB *client* can only dial 445, so a Windows-to-container test
needs either the host `Server` service stopped, or the client run from a VM or
another machine. `smbclient` and `mount.cifs` both accept a custom port, so
Linux and macOS clients are unaffected.

**Line endings.** `entrypoint.sh` with CRLF fails at startup with a misleading
"no such file or directory". `.gitattributes` prevents this and the Dockerfile
strips CR as a second line of defence. If you edit the script in a Windows
editor, save it as LF.

**Share permissions.** The container user needs read access to `./share`.
Docker Desktop bind mounts usually expose files as world-readable so this is a
non-issue there, but on the Linux build server either match `SMB_UID` to the
directory owner's UID or uncomment `force user = root` in
`config/smb.conf.tmpl`. The entrypoint logs a warning when it detects this.

**Changing the password.** It is applied on every container start, so
`docker compose up -d` after editing `.env` is enough. No rebuild needed.

**Not a hardened server.** Credentials are in plaintext in `.env` and the
container runs `smbd` as root so it can bind a privileged port. Fine for a
throwaway test fixture on a trusted network; do not expose it publicly.
