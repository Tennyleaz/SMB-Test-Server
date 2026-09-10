# SMB Test Server

A minimal containerised Samba server for exercising SMB **client** implementations.

- One named user, guest access refused outright
- Share is read-only through two independent layers
- Test files are **baked into the image** - no bind mount, no host setup
- Port, credentials, share name and protocol range are all configurable
- Logs go to `docker logs`, so auth failures are visible live

## Layout

```
Dockerfile
docker-compose.yml
.env.example            copy to .env
.gitattributes          forces LF - do not delete
.dockerignore           keeps .env and .git out of the build context
config/smb.conf.tmpl    edit this, not the rendered smb.conf
scripts/entrypoint.sh
scripts/gen-fixtures.sh generates the bulky test files at build time
share/                  committed test files, copied into the image at /share
```

## Share contents

`/share` is built into the image, so `docker compose up` needs no host folder
and every container serves an identical file set. `share/` in the repo holds
the small text fixtures; `scripts/gen-fixtures.sh` adds the bulky and awkward
ones during `docker build`.

| Path | What it is for |
| --- | --- |
| `readme.txt` | Smoke test: if you can read it, browse and read work. |
| `SHA256SUMS.txt` | Checksums for every file, to prove a read came back byte-for-byte. |
| `.hidden-file.txt` | Dotfile. SMB has no Unix hidden flag, so it should be listed. |
| `empty-file.txt`, `empty-dir/` | Zero-byte file, zero-entry directory. |
| `subfolder/`, `nested/a/b/c/` | Subdirectory traversal. |
| `deep-path/` | 20 levels deep, plus a 200-character filename. Path-length limits. |
| `text/` | LF, CRLF, no trailing newline, UTF-8 BOM, a 4096-character line, non-ASCII content. |
| `formats/` | csv, json, xml, md, log, ini - for clients that behave by extension. |
| `names/` | Spaces, `#`, `%`, `&`, `+`, brackets, parens, apostrophe, leading dash, mixed case, Chinese, Japanese, accented Latin, emoji. |
| `many-files/` | 256 files in one directory. Enumeration and paging. |
| `sizes/` | 1K / 64K / 1M random, 1M zeros, 10M random, a tiny binary. Read throughput. |
| `hostile-names/` | Names that are legal on Linux and illegal on Windows. Off by default. |

Verify a whole download against the manifest:

```sh
docker exec smb-test sh -c 'cd /share && sha256sum -c SHA256SUMS.txt' | grep -v ': OK$'
```

### Tuning what gets baked in

Build args, settable in `.env` (they are wired through `docker-compose.yml`).
Changing one needs a rebuild, not just a restart:

| Build arg | Default | Effect |
| --- | --- | --- |
| `FIXTURE_LARGE_MB` | `10` | Size of the big incompressible file. Random data, so it adds its full size to the image. `0` omits it. |
| `FIXTURE_SPARSE_MB` | `0` | Sparse file, in MiB - nearly free in the image, reads back as real bytes. Try `2048` for multi-GB transfer tests. |
| `FIXTURE_MANY_FILES` | `256` | Entries in `many-files/`. |
| `FIXTURE_DEEP_LEVELS` | `20` | Depth of `deep-path/`. |
| `FIXTURE_HOSTILE_NAMES` | `0` | `1` adds `hostile-names/`. Off by default because some clients handle that directory badly enough to obscure whatever you were actually testing. |

```sh
docker compose build --build-arg FIXTURE_LARGE_MB=0 --build-arg FIXTURE_HOSTILE_NAMES=1
docker compose up -d
```

### Serving your own files instead

Uncomment the `volumes:` block in `docker-compose.yml`. A bind mount at
`/share` shadows the baked-in contents rather than merging with them, so keep
the `:ro` - with a real host folder behind it, that flag is doing real work
again.

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

# 4. read works, including a subdirectory and a non-ASCII name
docker exec smb-test smbclient //localhost/testshare -U testuser%testpass \
    -c 'ls; get readme.txt /tmp/x; cd names; ls'

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

**Share permissions.** Not an issue for the baked-in share: it is root-owned
and world-readable, which is also read-only layer 2 of 2 (layer 1 is
`read only = yes` in `smb.conf`). It becomes an issue the moment you bind-mount
your own folder - then either match `SMB_UID` to the directory owner's UID or
uncomment `force user = root` in `config/smb.conf.tmpl`. The entrypoint logs a
warning when it detects that the container user cannot read the share.

**Editing the share needs a rebuild.** Files under `share/` are copied in at
build time, so run `docker compose up -d --build` after changing them. A plain
restart keeps serving the old image contents.

**Changing the password.** It is applied on every container start, so
`docker compose up -d` after editing `.env` is enough. No rebuild needed.

**Not a hardened server.** Credentials are in plaintext in `.env` and the
container runs `smbd` as root so it can bind a privileged port. Fine for a
throwaway test fixture on a trusted network; do not expose it publicly.
