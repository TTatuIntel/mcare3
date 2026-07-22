#!/usr/bin/env bash
# Run ON the EC2 server after code is uploaded to /var/www/mcare3
# Usage: sudo bash /var/www/mcare3/scripts/server-bootstrap-mcare3.sh

set -euo pipefail

APP_ROOT=/var/www/mcare3
BACKEND=$APP_ROOT/backend
WEB_ROOT=$APP_ROOT/frontend/build/web

echo "==> App root: $APP_ROOT"
test -d "$BACKEND" || { echo "Missing $BACKEND — upload the repo first"; exit 1; }

cd "$BACKEND"

if [ ! -f .env ]; then
  echo "Missing backend/.env — copy production .env before continuing"
  exit 1
fi

echo "==> Composer install"
composer install --no-dev --optimize-autoloader --no-interaction

echo "==> Ensure APP_KEY exists"
grep -q '^APP_KEY=base64:' .env || php artisan key:generate --force

echo "==> Storage link + caches"
php artisan storage:link || true
php artisan config:clear
php artisan route:clear
php artisan view:clear
php artisan config:cache
php artisan route:cache

echo "==> Permissions"
chown -R www-data:www-data storage bootstrap/cache
chmod -R ug+rwx storage bootstrap/cache

echo "==> Done bootstrap."
echo "Next:"
echo "  1) Create MySQL DB + user (see scripts/db-migrate-mcare3.sh notes)"
echo "  2) php artisan migrate --force"
echo "  3) Import dump if migrating old data"
echo "  4) Point Nginx to $BACKEND/public and $WEB_ROOT"
echo "  5) certbot for api.matendocare.com + app.matendocare.com"
