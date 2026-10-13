#!/usr/bin/env bash
# One dump of notefeed's database into ../data/dumps, and the old dumps of the same kind removed.
#
#   dump.sh <kind> <days to keep>      e.g.  dump.sh hourly 1
#
# The kind is only a name in front of the file: each kind is kept for its own time. A dump is written under a
# temporary name, read back with pg_restore, and only then given its real name, so a file named *.dump is always a
# whole one. Old dumps are removed only after a new one succeeded.
#
# The licenses (notefeed/notefeed #42) are a SQLite file of their own, ../data/licenses/licenses.db, and are saved next to each
# dump as <kind>-<time>.licenses.sqlite, with a consistent `sqlite3 .backup` (needs sqlite3 on the host), checked and kept the
# same days. A host without that file (no licenses sold yet) makes none.
# The images are not in the dump: they are the files in ../data/s3.
#
# To restore, with notefeed stopped (docker stop notefeed; docker start notefeed afterwards), into the running database:
#   docker exec -i notefeed-db pg_restore -U notefeed -d notefeed --clean --if-exists --no-owner --exit-on-error < data/dumps/<file>
# Then the image copy of the same day, see copy-images.sh. Tried 2026-10-10.
# The licenses, with notefeed stopped: cp data/dumps/<kind>-<time>.licenses.sqlite data/licenses/licenses.db
set -euo pipefail

kind=${1:?the kind of dump, e.g. hourly}
keep_days=${2:?how many days to keep dumps of this kind}
[[ $kind =~ ^[a-z][a-z0-9-]*$ ]] || { echo "dump: the kind may hold only a-z, 0-9 and -" >&2; exit 2; }
[[ $keep_days =~ ^[0-9]+$ ]] || { echo "dump: the days to keep must be a number" >&2; exit 2; }

container=${DUMP_DB_CONTAINER:-notefeed-db}
dir=${DUMP_DIR:-$(cd "$(dirname "$0")/.." && pwd)/data/dumps}

umask 077
mkdir -p "$dir"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
file="$dir/$kind-$stamp.dump"
tmp="$file.tmp"
licenses=${DUMP_LICENSES_DB:-$(cd "$(dirname "$0")/.." && pwd)/data/licenses/licenses.db}
ltmp="$dir/$kind-$stamp.licenses.sqlite.tmp"
trap 'rm -f "$tmp" "$ltmp"' EXIT

# The user and the database name are the container's own settings.
docker exec "$container" sh -c 'pg_dump --format=custom -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$tmp"
docker exec -i "$container" pg_restore --list < "$tmp" > /dev/null

# The licenses file, if there is one: copied by SQLite itself (safe while notefeed writes), then opened and checked.
if [[ -f $licenses ]]; then
  sqlite3 "$licenses" ".backup '$ltmp'"
  [[ $(sqlite3 "$ltmp" 'PRAGMA integrity_check;') == ok ]] || { echo "dump: the copy of the licenses file is not intact" >&2; exit 1; }
  mv "$ltmp" "$dir/$kind-$stamp.licenses.sqlite"
fi
mv "$tmp" "$file"

find "$dir" -maxdepth 1 -type f -name "$kind-*.dump" -mmin "+$((keep_days * 24 * 60))" -delete
find "$dir" -maxdepth 1 -type f -name "$kind-*.licenses.sqlite" -mmin "+$((keep_days * 24 * 60))" -delete
find "$dir" -maxdepth 1 -type f \( -name '*.dump.tmp' -o -name '*.licenses.sqlite.tmp' \) -mmin +60 -delete

echo "dump: $(basename "$file"), $(stat -c %s "$file") bytes"
