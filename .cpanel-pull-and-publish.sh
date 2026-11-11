#!/usr/bin/env bash
#
# Poll the public build repository and publish its latest build to the cPanel
# document root. Run this script from cPanel Cron Jobs every five minutes.
#
# Usage:
#   /bin/bash /home/alignedcloud/repositories/aligned-tech-deploy/.cpanel-pull-and-publish.sh \
#     /home/alignedcloud/repositories/aligned-tech-deploy /home/alignedcloud/public
#
# The repository is build-output only. Do not make manual edits there: this
# script deliberately makes it exactly match origin/main before every publish.
set -euo pipefail

REPOSITORY_DIR="${1:?Usage: $0 REPOSITORY_DIR WEB_ROOT}"
WEB_ROOT="${2:?Usage: $0 REPOSITORY_DIR WEB_ROOT}"
GIT_BIN="${GIT_BIN:-/usr/local/cpanel/3rdparty/bin/git}"
RSYNC_BIN="${RSYNC_BIN:-/usr/bin/rsync}"

if [[ ! -x "$GIT_BIN" ]]; then
  GIT_BIN="$(command -v git)"
fi

if [[ ! -d "$REPOSITORY_DIR/.git" ]]; then
  echo "ERROR: cPanel repository not found: $REPOSITORY_DIR" >&2
  exit 1
fi

mkdir -p "$WEB_ROOT"
"$GIT_BIN" -C "$REPOSITORY_DIR" fetch --prune origin main
"$GIT_BIN" -C "$REPOSITORY_DIR" reset --hard origin/main

if [[ -x "$RSYNC_BIN" ]]; then
  "$RSYNC_BIN" -a --delete \
    --exclude='.git' \
    --exclude='.cpanel.yml' \
    --exclude='.cpanel-pull-and-publish.sh' \
    "$REPOSITORY_DIR/" "$WEB_ROOT/"
else
  TAR_BIN="${TAR_BIN:-$(command -v tar || true)}"
  if [[ -z "$TAR_BIN" || ! -x "$TAR_BIN" ]]; then
    echo "ERROR: neither rsync nor tar is available to publish the site" >&2
    exit 1
  fi

  # Some shared cPanel plans omit rsync. tar copies the same build atomically
  # per file and keeps deployment metadata out of the document root. Unlike
  # rsync it leaves unreferenced files from an older build in place; those do
  # not affect the current site and are replaced on subsequent builds.
  echo "rsync not found; publishing with tar instead"
  "$TAR_BIN" \
    --exclude='.git' \
    --exclude='.cpanel.yml' \
    --exclude='.cpanel-pull-and-publish.sh' \
    -C "$REPOSITORY_DIR" -cf - . | "$TAR_BIN" -C "$WEB_ROOT" -xf -
fi

echo "Published $($GIT_BIN -C "$REPOSITORY_DIR" rev-parse --short HEAD) to $WEB_ROOT"
