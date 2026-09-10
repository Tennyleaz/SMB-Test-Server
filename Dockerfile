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

# Strip CRLF in case the script was checked out on Windows without .gitattributes
# taking effect, otherwise the shebang breaks with a confusing "not found" error.
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh \
    && chmod 0755 /usr/local/bin/entrypoint.sh \
    && mkdir -p /share /run/samba /var/lib/samba/private

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
