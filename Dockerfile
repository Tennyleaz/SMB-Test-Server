FROM alpine:3.20

# samba-common-tools provides smbpasswd/testparm, samba-client provides smbclient
# (used by the healthcheck and for in-container verification).
RUN apk add --no-cache \
        samba-server \
        samba-common-tools \
        samba-client \
        tini \
    && rm -rf /var/cache/apk/*

COPY config/smb.conf.tmpl /etc/samba/smb.conf.tmpl
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/gen-fixtures.sh /usr/local/bin/gen-fixtures.sh

# Strip CRLF in case the scripts were checked out on Windows without
# .gitattributes taking effect, otherwise the shebang breaks with a confusing
# "not found" error.
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh /usr/local/bin/gen-fixtures.sh \
    && chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/gen-fixtures.sh \
    && mkdir -p /share /run/samba /var/lib/samba/private

# --------------------------------------------------------------------------
# Test share contents, baked in. No host folder is mounted, so every container
# starts from the same known file set.
#
#   FIXTURE_LARGE_MB      size of the big incompressible read-throughput file.
#                         Random data, so it adds its full size to the image.
#                         0 omits it.
#   FIXTURE_SPARSE_MB     sparse file for very large transfers. Nearly free in
#                         the image, reads back as real bytes. 0 omits it.
#   FIXTURE_MANY_FILES    entries in many-files/, for directory enumeration.
#   FIXTURE_DEEP_LEVELS   depth of deep-path/, for path-length limits.
#   FIXTURE_HOSTILE_NAMES 1 adds hostile-names/ - filenames that are legal on
#                         Linux but illegal on Windows. Off by default because
#                         some clients handle that directory badly enough to
#                         obscure whatever you were actually testing.
#
# Override per build, e.g.:
#   docker compose build --build-arg FIXTURE_LARGE_MB=0
# --------------------------------------------------------------------------
ARG FIXTURE_LARGE_MB=10
ARG FIXTURE_SPARSE_MB=0
ARG FIXTURE_MANY_FILES=256
ARG FIXTURE_DEEP_LEVELS=20
ARG FIXTURE_HOSTILE_NAMES=0

COPY share/ /share/

# Ownership plus mode is read-only layer 2 of 2: root owns every file and
# nothing is group- or other-writable, so the unix account smbd runs as cannot
# write here even if `read only = yes` were removed from smb.conf. (The `:ro`
# bind mount that used to be the third layer is gone along with the mount
# itself - there is no host data left to protect.)
# SHARE_PATH is passed explicitly because the ENV block below has not run yet.
RUN SHARE_PATH=/share /usr/local/bin/gen-fixtures.sh \
    && chown -R root:root /share \
    && find /share -type d -exec chmod 0555 {} + \
    && find /share -type f -exec chmod 0444 {} +

# Defaults. Every one of these can be overridden at run time; nothing secret is
# baked into an image layer, the password is only ever set by the entrypoint.
ENV SMB_USER=testuser \
    SMB_PASS=testpass \
    SMB_SHARE=testshare \
    SMB_PORT=445 \
    SMB_UID=1000 \
    SMB_WORKGROUP=WORKGROUP \
    SMB_NETBIOS_NAME=SMBTEST \
    SMB_MIN_PROTOCOL=SMB2 \
    SMB_MAX_PROTOCOL=SMB3 \
    SMB_NTLM_AUTH=ntlmv2-only \
    SMB_LOG_LEVEL=1 \
    SHARE_PATH=/share

EXPOSE 445/tcp

# ${SMB_PORT%% *} takes the first port, in case SMB_PORT is a space-separated list.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD smbclient -L "localhost" -p "${SMB_PORT%% *}" \
        -U "${SMB_USER}%${SMB_PASS}" >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
