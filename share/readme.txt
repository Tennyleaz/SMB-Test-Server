SMB Test Server - read-only test share
======================================

This share is baked into the container image. Nothing is mounted from the
host, so every container starts from an identical, known-good file set.

If you can read this file over SMB, browsing and file reads both work.
Try writing anywhere in this share: it must fail.

Layout
------
  readme.txt              this file
  SHA256SUMS.txt          checksums for every file, for verifying reads
  .hidden-file.txt        dotfile - visible to SMB, hidden to some clients
  empty-file.txt          zero bytes
  empty-dir/              empty directory
  subfolder/              subdirectory traversal
  nested/a/b/c/           a few levels down
  deep-path/              20 levels down, for path-length limits
  text/                   line endings, BOM, long lines, UTF-8 content
  formats/                csv, json, xml, md, log, ini
  names/                  spaces, punctuation, mixed case, non-ASCII names
  many-files/             a directory with many entries, for enumeration
  sizes/                  1K .. 10M files, for read throughput
  hostile-names/          only present when built with FIXTURE_HOSTILE_NAMES=1

Generated at image build time by scripts/gen-fixtures.sh:
  deep-path/, many-files/, sizes/, hostile-names/, empty-dir/,
  empty-file.txt, text/utf8-bom.txt, SHA256SUMS.txt
Everything else is committed under share/ in the repo.
