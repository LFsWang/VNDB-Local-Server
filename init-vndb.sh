#!/bin/sh
set -e

PGVER=17

# ── Devuser phase (called recursively) ──
if [ "$1" = "_devuser_init" ]; then
    cd /vndb

    echo "[4/7] Building assets..."
    make -j4

    echo "[5/7] Setting up var directory..."
    util/setup-var.sh

    echo "[6/7] Initializing PostgreSQL..."

    if [ ! -d docker/pg$PGVER ]; then
        mkdir -p docker/pg$PGVER
        initdb -D docker/pg$PGVER --locale en_US.UTF-8 -A trust
    fi

    pg_ctl -D /vndb/docker/pg$PGVER -l /vndb/docker/pg$PGVER/logfile start
    sleep 2
    until pg_isready -q; do sleep 1; done

    if [ ! -f docker/pg$PGVER/vndb-init-done ]; then
        echo "  Creating database and roles..."
        psql postgres -f sql/superuser_init.sql
        psql -U devuser vndb -f sql/vndbid.sql
        echo "ALTER ROLE vndb       LOGIN" | psql postgres
        echo "ALTER ROLE vndb_site  LOGIN" | psql postgres
        echo "ALTER ROLE vndb_multi LOGIN" | psql postgres

        echo "  Loading full schema..."
        psql postgres -c "ALTER ROLE vndb SUPERUSER;"
        psql -U vndb -f sql/all.sql
        psql postgres -c "ALTER ROLE vndb NOSUPERUSER;"

        # Import data dump if available
        if [ -f /dump/vndb-db.tar.zst ]; then
            echo "  Extracting data dump..."
            mkdir -p /tmp/vndb-dump
            cd /tmp/vndb-dump
            zstd -d /dump/vndb-db.tar.zst --stdout | tar xf -

            DBDIR="/tmp/vndb-dump/db"
            if [ ! -d "$DBDIR" ]; then
                echo "  ERROR: No db/ directory in dump"
            else
                echo "  Importing data..."
                psql postgres -c "ALTER ROLE vndb SUPERUSER;"

                # Generate import script:
                # 1) Disable triggers/FK checks
                # 2) Truncate ALL tables first (avoid CASCADE removing already-imported data)
                # 3) Copy all data
                # 4) Re-enable triggers
                SCRIPT="/tmp/vndb-dump/run_import.sql"
                echo "SET session_replication_role = 'replica';" > "$SCRIPT"

                # Phase 1: Truncate all tables that will be imported
                for f in "$DBDIR"/*; do
                    case "$f" in *.header) continue ;; esac
                    [ -f "$f" ] || continue
                    table=$(basename "$f")
                    [ -f "$f.header" ] || continue
                    echo "TRUNCATE \"$table\" CASCADE;" >> "$SCRIPT"
                done

                # Phase 2: Copy all data
                for f in "$DBDIR"/*; do
                    case "$f" in *.header) continue ;; esac
                    [ -f "$f" ] || continue
                    table=$(basename "$f")
                    headerfile="$f.header"
                    [ -f "$headerfile" ] || continue

                    cols=$(tr '\t' ',' < "$headerfile" | tr -d '\n' | sed 's/,$//')
                    echo "\\copy \"$table\"($cols) FROM '$f'" >> "$SCRIPT"
                done

                echo "SET session_replication_role = 'origin';" >> "$SCRIPT"

                echo "  Running import (this takes a few minutes)..."
                psql -U vndb vndb -f "$SCRIPT" 2>&1 | while IFS= read -r line; do
                    case "$line" in
                        COPY*) echo "    $line" ;;
                        *ERROR*) echo "    $line" ;;
                    esac
                done

                psql postgres -c "ALTER ROLE vndb NOSUPERUSER;"

                # Fix tables where dump only exports non-hidden rows
                # but schema defaults hidden=true
                echo "  Fixing hidden flags for imported data..."
                psql -U vndb vndb -c "
                    UPDATE tags SET hidden = false WHERE hidden;
                    UPDATE traits SET hidden = false WHERE hidden;
                " 2>/dev/null || true
            fi

            rm -rf /tmp/vndb-dump
            cd /vndb
        else
            echo "  No data dump found. Using empty database."
        fi

        # Re-apply permissions (perms.sql needs SUPERUSER and :DBNAME)
        echo "  Applying permissions..."
        psql postgres -c "ALTER ROLE vndb SUPERUSER;"
        psql -U vndb vndb -v DBNAME=vndb -f sql/perms.sql 2>/dev/null || true
        psql postgres -c "ALTER ROLE vndb NOSUPERUSER;"

        # Ensure seed data
        psql -U vndb vndb -c "
            INSERT INTO global_settings (id) VALUES (TRUE) ON CONFLICT DO NOTHING;
            INSERT INTO users (id, username, notifyopts) VALUES ('u1', 'multi', 0) ON CONFLICT DO NOTHING;
        " 2>/dev/null || true

        # Refresh stats cache
        echo "  Refreshing stats..."
        psql -U vndb vndb -c "
            INSERT INTO stats_cache (section, count) VALUES
                ('vn', 0), ('producers', 0), ('releases', 0),
                ('chars', 0), ('staff', 0), ('tags', 0), ('traits', 0)
                ON CONFLICT (section) DO NOTHING;
            UPDATE stats_cache SET count = COALESCE((SELECT count(*) FROM vn WHERE NOT hidden), 0) WHERE section = 'vn';
            UPDATE stats_cache SET count = COALESCE((SELECT count(*) FROM producers WHERE NOT hidden), 0) WHERE section = 'producers';
            UPDATE stats_cache SET count = COALESCE((SELECT count(*) FROM releases WHERE NOT hidden), 0) WHERE section = 'releases';
            UPDATE stats_cache SET count = COALESCE((SELECT count(*) FROM chars WHERE NOT hidden), 0) WHERE section = 'chars';
            UPDATE stats_cache SET count = COALESCE((SELECT count(*) FROM staff WHERE NOT hidden), 0) WHERE section = 'staff';
            UPDATE stats_cache SET count = COALESCE((SELECT count(*) FROM tags WHERE NOT hidden), 0) WHERE section = 'tags';
            UPDATE stats_cache SET count = COALESCE((SELECT count(*) FROM traits WHERE NOT hidden), 0) WHERE section = 'traits';
        " 2>/dev/null || true

        # Generate change records for all entries (required for detail pages)
        echo "  Generating change records..."
        psql postgres -c "ALTER ROLE vndb SUPERUSER;"
        psql -U vndb vndb -c "
            SET session_replication_role = 'replica';
            INSERT INTO changes (itemid, rev, ihid, ilock, requester, comments)
            SELECT id, 1, hidden, locked, 'u1', 'Imported from dump' FROM vn ON CONFLICT (itemid, rev) DO NOTHING;
            INSERT INTO changes (itemid, rev, ihid, ilock, requester, comments)
            SELECT id, 1, hidden, locked, 'u1', 'Imported from dump' FROM releases ON CONFLICT (itemid, rev) DO NOTHING;
            INSERT INTO changes (itemid, rev, ihid, ilock, requester, comments)
            SELECT id, 1, hidden, locked, 'u1', 'Imported from dump' FROM chars ON CONFLICT (itemid, rev) DO NOTHING;
            INSERT INTO changes (itemid, rev, ihid, ilock, requester, comments)
            SELECT id, 1, hidden, locked, 'u1', 'Imported from dump' FROM producers ON CONFLICT (itemid, rev) DO NOTHING;
            INSERT INTO changes (itemid, rev, ihid, ilock, requester, comments)
            SELECT id, 1, hidden, locked, 'u1', 'Imported from dump' FROM staff ON CONFLICT (itemid, rev) DO NOTHING;
            SET session_replication_role = 'origin';
        " 2>/dev/null || true
        psql postgres -c "ALTER ROLE vndb NOSUPERUSER;"

        # Rebuild caches (vncache, vote stats, tags, traits, search)
        echo "  Rebuilding VN cache (released, languages, platforms, developers)..."
        psql -U vndb vndb -c "SELECT update_vncache(NULL);" 2>/dev/null || true

        echo "  Rebuilding vote statistics..."
        psql -U vndb vndb -c "SELECT update_vnvotestats();" 2>/dev/null || true

        echo "  Rebuilding tag cache (this may take a few minutes)..."
        psql -U vndb vndb -c "SELECT tag_vn_calc(NULL);" 2>/dev/null || true

        echo "  Rebuilding trait cache..."
        psql -U vndb vndb -c "SELECT traits_chars_calc(NULL);" 2>/dev/null || true

        echo "  Rebuilding search cache (this may take 5-10 minutes)..."
        psql -U vndb vndb -f /vndb/sql/rebuild-search-cache.sql 2>/dev/null || true

        # Update sequences
        echo "  Updating sequences..."
        psql -U vndb vndb -c "
            DO \$\$
            DECLARE r RECORD; max_id bigint;
            BEGIN
                FOR r IN
                    SELECT s.relname AS seq_name, t.relname AS table_name, a.attname AS col_name
                    FROM pg_class s
                    JOIN pg_depend d ON d.objid = s.oid
                    JOIN pg_class t ON t.oid = d.refobjid
                    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
                    WHERE s.relkind = 'S'
                LOOP
                    BEGIN
                        EXECUTE format('SELECT COALESCE(max(%I::text::bigint), 1) FROM %I', r.col_name, r.table_name) INTO max_id;
                        EXECUTE format('SELECT setval(%L, %s)', r.seq_name, max_id);
                    EXCEPTION WHEN OTHERS THEN NULL;
                    END;
                END LOOP;
            END \$\$;
        " 2>/dev/null || true

        touch docker/pg$PGVER/vndb-init-done
        echo "  Database initialization complete!"
    else
        echo "  Database already initialized."
    fi

    echo "[7/7] Starting VNDB dev server on port 3000..."
    echo ""
    echo "=========================================="
    echo "  VNDB is ready at http://localhost:3000"
    echo "  API: http://localhost:3000/api/kana"
    echo "=========================================="
    echo ""
    exec util/vndb-dev-server.pl
fi

# ── Root phase (runs first) ──
echo "=== VNDB Local Setup ==="

echo "[1/7] Creating dev user..."
USER_UID=$(stat -c '%u' /vndb)
USER_GID=$(stat -c '%g' /vndb)
if test "$USER_UID" -eq 0; then
    addgroup devgroup 2>/dev/null || true
    adduser -s /bin/sh -D devuser 2>/dev/null || true
else
    addgroup -g "$USER_GID" devgroup 2>/dev/null || true
    adduser -s /bin/sh -u "$USER_UID" -G devgroup -D devuser 2>/dev/null || true
fi
install -d -o devuser -g devgroup /run/postgresql

echo "[2/7] Installing vndbid extension..."
mkdir -p /tmp/vndbid
cp /vndb/sql/c/vndbfuncs.c /vndb/sql/c/Makefile /tmp/vndbid
make -C /tmp/vndbid install

echo "[3/7] Installing zstd..."
apk add --no-cache zstd >/dev/null 2>&1 || true

# Switch to devuser for the rest
exec su devuser -c "/bin/sh /init-vndb.sh _devuser_init"
