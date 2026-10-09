#!/usr/bin/env bash
# One copy of the image store's files (../data/s3) into ../data/image-copies, and the old copies of the same kind removed.
#
#   copy-images.sh <kind> <days to keep>      e.g.  copy-images.sh daily 30
#
# Each run is a folder, <kind>-<time>, with every file of the store. A file that is unchanged since the previous copy of the
# kind is a hard link to it (rsync --link-dest), so thirty copies cost one copy plus what changed in between. A copy is made
# under a temporary name and renamed when complete, so a folder named <kind>-<time> is always a whole copy. Old copies are
# removed only after a new one succeeded.
#
# To purge one image from every copy (a takedown; the key is the file's name): find image-copies -type f -name '<key>' -delete
# The database is not in a copy: that is dump.sh. A restore is both: the dump into the database, a copy back into data/s3.
set -euo pipefail

kind=${1:?the kind of copy, e.g. daily}
keep_days=${2:?how many days to keep copies of this kind}
[[ $kind =~ ^[a-z][a-z0-9-]*$ ]] || { echo "copy-images: the kind may hold only a-z, 0-9 and -" >&2; exit 2; }
[[ $keep_days =~ ^[0-9]+$ ]] || { echo "copy-images: the days to keep must be a number" >&2; exit 2; }

base=$(cd "$(dirname "$0")/.." && pwd)
src=${COPY_SRC:-$base/data/s3}
dir=${COPY_DIR:-$base/data/image-copies}
[[ -d $src ]] || { echo "copy-images: no image store at $src" >&2; exit 1; }

umask 077
mkdir -p "$dir"
dest="$dir/$kind-$(date -u +%Y%m%dT%H%M%SZ)"
tmp="$dest.tmp"
trap 'rm -rf "$tmp"' EXIT

# The newest complete copy of this kind, for the hard links.
prev=$(find "$dir" -maxdepth 1 -mindepth 1 -type d -name "$kind-*Z" | sort | tail -n 1)
rsync -a --delete ${prev:+--link-dest="$prev"} "$src/" "$tmp/"
mv "$tmp" "$dest"
touch "$dest" # rsync gave the folder the store's own time; retention goes by when the copy was made

find "$dir" -maxdepth 1 -mindepth 1 -type d -name "$kind-*Z" -mmin "+$((keep_days * 24 * 60))" -exec rm -rf {} +
find "$dir" -maxdepth 1 -mindepth 1 -type d -name '*.tmp' -mmin +1440 -exec rm -rf {} +

echo "copy-images: $(basename "$dest"), $(find "$dest" -type f | wc -l) files, $(du -sh --apparent-size "$dest" | cut -f1)"
