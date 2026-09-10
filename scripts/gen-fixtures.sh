#!/bin/sh
#
# Generates the parts of the test share that should not live in git: bulky
# binaries, directories with hundreds of entries, deep paths, empty files and
# empty directories, and filenames that cannot be checked out on Windows.
#
# Run at image build time by the Dockerfile, after share/ has been copied in.
# Sizes are controlled by build args - see the ARG block in the Dockerfile.
#
set -eu

SHARE_PATH="${SHARE_PATH:-/share}"
FIXTURE_LARGE_MB="${FIXTURE_LARGE_MB:-10}"
FIXTURE_SPARSE_MB="${FIXTURE_SPARSE_MB:-0}"
FIXTURE_MANY_FILES="${FIXTURE_MANY_FILES:-256}"
FIXTURE_DEEP_LEVELS="${FIXTURE_DEEP_LEVELS:-20}"
FIXTURE_HOSTILE_NAMES="${FIXTURE_HOSTILE_NAMES:-0}"

log() { printf '[gen-fixtures] %s\n' "$*"; }

[ -d "$SHARE_PATH" ] || { printf '[gen-fixtures] ERROR: %s missing\n' "$SHARE_PATH" >&2; exit 1; }
cd "$SHARE_PATH"

# --------------------------------------------------------------------------
# Empty file and empty directory. git tracks neither, so they are made here.
# --------------------------------------------------------------------------
log "empty file and empty directory"
: > empty-file.txt
mkdir -p empty-dir

# --------------------------------------------------------------------------
# A UTF-8 BOM file. Committing exact leading bytes is fragile once
# .gitattributes starts normalising text, so it is written here instead.
# --------------------------------------------------------------------------
log "text/utf8-bom.txt"
printf '\357\273\277UTF-8 with a byte order mark.\n' > text/utf8-bom.txt

# --------------------------------------------------------------------------
# Sizes. Random data is incompressible, so it exercises real throughput and
# also adds its full weight to the image - hence the build args.
# --------------------------------------------------------------------------
log "sizes: 1K, 64K, 1M random + 1M zeros${FIXTURE_LARGE_MB:+, ${FIXTURE_LARGE_MB}M random}"
mkdir -p sizes
dd if=/dev/urandom of=sizes/random-1K.bin  bs=1024 count=1  2>/dev/null
dd if=/dev/urandom of=sizes/random-64K.bin bs=1024 count=64 2>/dev/null
dd if=/dev/urandom of=sizes/random-1M.bin  bs=1048576 count=1 2>/dev/null
dd if=/dev/zero    of=sizes/zeros-1M.bin   bs=1048576 count=1 2>/dev/null

if [ "$FIXTURE_LARGE_MB" -gt 0 ]; then
    dd if=/dev/urandom of="sizes/random-${FIXTURE_LARGE_MB}M.bin" \
       bs=1048576 count="$FIXTURE_LARGE_MB" 2>/dev/null
fi

if [ "$FIXTURE_SPARSE_MB" -gt 0 ]; then
    # Sparse: costs almost nothing in the image but reads back as real bytes,
    # which is how to test multi-gigabyte transfers without a huge image.
    log "sizes: ${FIXTURE_SPARSE_MB}M sparse"
    truncate -s "${FIXTURE_SPARSE_MB}M" "sizes/sparse-${FIXTURE_SPARSE_MB}M.bin"
fi

# A tiny non-text file, so clients have something to sniff as binary.
printf '\211PNG\r\n\032\n\000\000\000\rIHDR\000\000\000\001\000\000\000\001' \
    > sizes/tiny-binary.bin

# --------------------------------------------------------------------------
# Directory with many entries, for enumeration and paging behaviour.
# --------------------------------------------------------------------------
log "many-files: ${FIXTURE_MANY_FILES} entries"
mkdir -p many-files
i=1
while [ "$i" -le "$FIXTURE_MANY_FILES" ]; do
    n=$(printf '%04d' "$i")
    printf 'file %s of %s\n' "$n" "$FIXTURE_MANY_FILES" > "many-files/file-${n}.txt"
    i=$((i + 1))
done

# --------------------------------------------------------------------------
# Deep path and a long filename. Generated rather than committed because a
# Windows checkout of the repo would hit MAX_PATH first.
# --------------------------------------------------------------------------
log "deep-path: ${FIXTURE_DEEP_LEVELS} levels, plus a 200-character filename"
deep=deep-path
i=1
while [ "$i" -le "$FIXTURE_DEEP_LEVELS" ]; do
    deep="${deep}/level-$(printf '%02d' "$i")"
    i=$((i + 1))
done
mkdir -p "$deep"
printf 'Bottom of a %s-level path.\n' "$FIXTURE_DEEP_LEVELS" > "${deep}/bottom.txt"

longname=$(awk 'BEGIN { while (length(s) < 196) s = s "long-name-"; print substr(s, 1, 196) }')
printf 'A 200-character filename.\n' > "deep-path/${longname}.txt"

# --------------------------------------------------------------------------
# Names that are legal on Linux but illegal on Windows. Off by default: some
# clients handle a directory containing these badly enough to obscure whatever
# you were actually testing. Build with FIXTURE_HOSTILE_NAMES=1 to include.
# --------------------------------------------------------------------------
if [ "$FIXTURE_HOSTILE_NAMES" = "1" ]; then
    log "hostile-names: enabled"
    mkdir -p hostile-names
    printf 'A question mark.\n'   > 'hostile-names/question?.txt'
    printf 'An asterisk.\n'       > 'hostile-names/star*.txt'
    printf 'A colon.\n'           > 'hostile-names/colon:name.txt'
    printf 'A backslash.\n'       > 'hostile-names/back\slash.txt'
    printf 'A pipe.\n'            > 'hostile-names/pipe|name.txt'
    printf 'Angle brackets.\n'    > 'hostile-names/angle<brackets>.txt'
    printf 'A trailing space.\n'  > 'hostile-names/trailing space .txt'
    printf 'A trailing dot.\n'    > 'hostile-names/trailing.dot.'
    printf 'A DOS device name.\n' > 'hostile-names/CON.txt'
    # Deliberately no newline-in-filename fixture: busybox sha256sum does not
    # escape it, which would corrupt SHA256SUMS.txt below.
else
    log "hostile-names: skipped (set FIXTURE_HOSTILE_NAMES=1 to include)"
fi

# --------------------------------------------------------------------------
# Checksums, so a client can prove a read came back byte-for-byte. Written
# last so it covers everything above. Excludes itself.
# --------------------------------------------------------------------------
log "SHA256SUMS.txt"
find . -type f ! -name SHA256SUMS.txt -print0 \
    | sort -z \
    | xargs -0 sha256sum > SHA256SUMS.txt

log "done: $(find . -type f | wc -l) files, $(find . -type d | wc -l) directories, $(du -sh . | cut -f1) total"
