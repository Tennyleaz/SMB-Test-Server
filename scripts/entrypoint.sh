#!/bin/sh
set -eu

SMB_USER="${SMB_USER:-testuser}"
SMB_PASS="${SMB_PASS:-testpass}"
SMB_SHARE="${SMB_SHARE:-testshare}"
SMB_PORT="${SMB_PORT:-445}"
SMB_UID="${SMB_UID:-1000}"
SMB_WORKGROUP="${SMB_WORKGROUP:-WORKGROUP}"
SMB_NETBIOS_NAME="${SMB_NETBIOS_NAME:-SMBTEST}"
SMB_MIN_PROTOCOL="${SMB_MIN_PROTOCOL:-SMB2}"
SMB_MAX_PROTOCOL="${SMB_MAX_PROTOCOL:-SMB3}"
SMB_NTLM_AUTH="${SMB_NTLM_AUTH:-ntlmv2-only}"
SMB_LOG_LEVEL="${SMB_LOG_LEVEL:-1}"
SHARE_PATH="${SHARE_PATH:-/share}"

TMPL=/etc/samba/smb.conf.tmpl
CONF=/etc/samba/smb.conf

log() { printf '[entrypoint] %s\n' "$*"; }
die() { printf '[entrypoint] ERROR: %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------
# Sanity checks
# --------------------------------------------------------------------------
# /share is baked into the image, so a missing path means either a broken build
# or SHARE_PATH pointing somewhere that was never mounted.
[ -d "$SHARE_PATH" ] || die "share path ${SHARE_PATH} does not exist (bad build, or SHARE_PATH overridden without a matching mount?)"

case "$SMB_USER" in
    ''|*[!a-zA-Z0-9_.-]*) die "SMB_USER '${SMB_USER}' contains characters that are unsafe in smb.conf" ;;
esac

if [ "$SMB_MIN_PROTOCOL" = "NT1" ]; then
    log "WARNING: SMB1/NT1 enabled. This is for legacy client testing only."
    log "WARNING: if authentication fails, also set SMB_NTLM_AUTH=yes"
fi

# --------------------------------------------------------------------------
# Unix account that Samba authenticates against
# --------------------------------------------------------------------------
if ! id -u "$SMB_USER" >/dev/null 2>&1; then
    log "creating unix user ${SMB_USER} (uid ${SMB_UID})"
    addgroup -g "$SMB_UID" "$SMB_USER" 2>/dev/null || addgroup "$SMB_USER"
    adduser -S -D -H -u "$SMB_UID" -G "$SMB_USER" -s /sbin/nologin "$SMB_USER"
fi

# --------------------------------------------------------------------------
# Samba password. Set on every start so changing SMB_PASS takes effect on
# restart without needing a rebuild or a wiped passdb.
# --------------------------------------------------------------------------
log "setting samba password for ${SMB_USER}"
printf '%s\n%s\n' "$SMB_PASS" "$SMB_PASS" | smbpasswd -a -s "$SMB_USER" >/dev/null
smbpasswd -e "$SMB_USER" >/dev/null

# --------------------------------------------------------------------------
# Render smb.conf from the template
# --------------------------------------------------------------------------
log "rendering ${CONF}"
sed \
    -e "s|__SMB_USER__|${SMB_USER}|g" \
    -e "s|__SMB_SHARE__|${SMB_SHARE}|g" \
    -e "s|__SMB_PORT__|${SMB_PORT}|g" \
    -e "s|__SMB_WORKGROUP__|${SMB_WORKGROUP}|g" \
    -e "s|__SMB_NETBIOS_NAME__|${SMB_NETBIOS_NAME}|g" \
    -e "s|__SMB_MIN_PROTOCOL__|${SMB_MIN_PROTOCOL}|g" \
    -e "s|__SMB_MAX_PROTOCOL__|${SMB_MAX_PROTOCOL}|g" \
    -e "s|__SMB_NTLM_AUTH__|${SMB_NTLM_AUTH}|g" \
    -e "s|__SMB_LOG_LEVEL__|${SMB_LOG_LEVEL}|g" \
    -e "s|__SHARE_PATH__|${SHARE_PATH}|g" \
    "$TMPL" > "$CONF"

# Fail fast on a malformed config rather than looping on smbd startup.
testparm -s "$CONF" >/dev/null || die "smb.conf failed validation"

# --------------------------------------------------------------------------
# Warn about the classic permission trap: files the container user can't read.
# --------------------------------------------------------------------------
# Cannot trip on the baked-in share, which is root-owned and world-readable.
# Still worth checking, because SHARE_PATH can be pointed at a bind mount.
if ! su -s /bin/sh "$SMB_USER" -c "test -r '${SHARE_PATH}'" 2>/dev/null; then
    log "WARNING: ${SMB_USER} cannot read ${SHARE_PATH}."
    log "WARNING: fix the host permissions, set SMB_UID to the owner's uid,"
    log "WARNING: or uncomment 'force user = root' in config/smb.conf.tmpl"
fi

log "share    : //<host>/${SMB_SHARE}  (read-only)"
log "contents : $(find "$SHARE_PATH" -type f 2>/dev/null | wc -l) files, $(find "$SHARE_PATH" -type d 2>/dev/null | wc -l) directories"
log "user     : ${SMB_USER}"
log "port     : ${SMB_PORT}"
log "protocol : ${SMB_MIN_PROTOCOL} .. ${SMB_MAX_PROTOCOL}"
log "guest    : disabled"

exec smbd --foreground --no-process-group "$@"
