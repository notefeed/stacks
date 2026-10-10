#!/usr/bin/env bash
# One dump of notefeed's database into ../data/dumps, and the old dumps of the same kind removed.
#
#   dump.sh <kind> <days to keep>      e.g.  dump.sh hourly 1
#
# The kind is only a name in front of the file: each kind is kept for its own time. A dump is written under a
# temporary name, read back with pg_restore, and only then given its real name, so a file named *.dump is always a
# whole one. Old dumps are removed only after a new one succeeded.
#
# The images are not in the dump: they are the files in ../data/s3.
#
# To restore, with notefeed stopped (docker stop notefeed; docker start notefeed afterwards), into the running database:
#   docker exec -i notefeed-db pg_restore -U notefeed -d notefeed --clean --if-exists --no-owner --exit-on-error < data/dumps/<file>
# Then the image copy of the same day, see copy-images.sh. Tried 2026-10-10.
set -euo pipefail

kind=${1:?the kind of dump, e.g. hourly}
keep_days=${2:?how many days to keep dumps of this kind}
[[ $kind =~ ^[a-z][a-z0-9-]*$ ]] || { echo "dump: the kind may hold only a-z, 0-9 and -" >&2; exit 2; }
[[ $keep_days =~ ^[0-9]+$ ]] || { echo "dump: the days to keep must be a number" >&2; exit 2; }

container=${DUMP_DB_CONTAINER:-notefeed-db}
dir=${DUMP_DIR:-$(cd "$(dirname "$0")/.." && pwd)/data/dumps}

umask 077
mkdir -p "$dir"
file="$dir/$kind-$(date -u +%Y%m%dT%H%M%SZ).dump"
tmp="$file.tmp"
trap 'rm -f "$tmp"' EXIT

# The user and the database name are the container's own settings.
docker exec "$container" sh -c 'pg_dump --format=custom -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$tmp"
docker exec -i "$container" pg_restore --list < "$tmp" > /dev/null
mv "$tmp" "$file"

find "$dir" -maxdepth 1 -type f -name "$kind-*.dump" -mmin "+$((keep_days * 24 * 60))" -delete
find "$dir" -maxdepth 1 -type f -name '*.dump.tmp' -mmin +60 -delete

echo "dump: $(basename "$file"), $(stat -c %s "$file") bytes"
