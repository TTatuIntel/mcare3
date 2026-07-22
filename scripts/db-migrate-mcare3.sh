#!/usr/bin/env bash
# Database migrate (old → new) then delete old — run ON the EC2 server.
#
# Flow:
#   A. Create NEW database (mcare3)
#   B. Import dump from OLD database (or run fresh migrate)
#   C. Point backend/.env at the NEW database
#   D. Verify the app
#   E. ONLY THEN drop the OLD database
#
# Usage examples:
#   # Fresh install (no old data):
#   sudo bash scripts/db-migrate-mcare3.sh fresh
#
#   # Import a dump file into the new DB:
#   sudo bash scripts/db-migrate-mcare3.sh import /tmp/mcare_old.sql
#
#   # After you confirm live works — delete old DB (destructive!):
#   sudo bash scripts/db-migrate-mcare3.sh drop-old OLD_DB_NAME

set -euo pipefail

ACTION=${1:-}
ARG=${2:-}

NEW_DB=mcare3
NEW_USER=mcare3
# Change this password before running (or export MCARE3_DB_PASSWORD=...)
NEW_PASS=${MCARE3_DB_PASSWORD:-ChangeMe_StrongPassword_Here}

mysql_root() {
  mysql -u root "$@"
}

case "$ACTION" in
  fresh)
    echo "==> Creating database $NEW_DB and user $NEW_USER"
    mysql_root <<SQL
CREATE DATABASE IF NOT EXISTS \`$NEW_DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$NEW_USER'@'localhost' IDENTIFIED BY '$NEW_PASS';
GRANT ALL PRIVILEGES ON \`$NEW_DB\`.* TO '$NEW_USER'@'localhost';
FLUSH PRIVILEGES;
SQL
    echo "==> Update /var/www/mcare3/backend/.env:"
    echo "    DB_DATABASE=$NEW_DB"
    echo "    DB_USERNAME=$NEW_USER"
    echo "    DB_PASSWORD=$NEW_PASS"
    echo "==> Then: cd /var/www/mcare3/backend && php artisan migrate --force"
    ;;

  import)
    DUMP=$ARG
    test -f "$DUMP" || { echo "Dump not found: $DUMP"; exit 1; }
    echo "==> Ensuring $NEW_DB exists"
    mysql_root <<SQL
CREATE DATABASE IF NOT EXISTS \`$NEW_DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$NEW_USER'@'localhost' IDENTIFIED BY '$NEW_PASS';
GRANT ALL PRIVILEGES ON \`$NEW_DB\`.* TO '$NEW_USER'@'localhost';
FLUSH PRIVILEGES;
SQL
    echo "==> Importing $DUMP into $NEW_DB"
    mysql -u root "$NEW_DB" < "$DUMP"
    echo "==> Import complete. Point .env DB_* to $NEW_DB / $NEW_USER, then:"
    echo "    php artisan migrate --force   # applies any newer migrations"
    echo "    php artisan config:clear"
    ;;

  drop-old)
    OLD_DB=$ARG
    test -n "$OLD_DB" || { echo "Usage: $0 drop-old OLD_DB_NAME"; exit 1; }
    if [ "$OLD_DB" = "$NEW_DB" ]; then
      echo "Refusing to drop the new database ($NEW_DB)"
      exit 1
    fi
    echo "WARNING: This permanently deletes database '$OLD_DB'"
    read -r -p "Type the old DB name to confirm: " CONFIRM
    if [ "$CONFIRM" != "$OLD_DB" ]; then
      echo "Cancelled."
      exit 1
    fi
    mysql_root -e "DROP DATABASE \`$OLD_DB\`;"
    echo "==> Dropped $OLD_DB"
    ;;

  *)
    cat <<EOF
Usage:
  $0 fresh                         Create empty $NEW_DB + user
  $0 import /path/to/dump.sql      Import old dump into $NEW_DB
  $0 drop-old OLD_DB_NAME          Delete old DB AFTER live verify

Export OLD data first (on the machine that has the old DB):
  mysqldump -u root -p OLD_DB_NAME > /tmp/mcare_old.sql
EOF
    exit 1
    ;;
esac
