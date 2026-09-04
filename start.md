# mCare — How to run

Backend runs on port **8010** (8000 is taken).

## First-time backend setup (once)

```bash
cd backend
composer install
cp .env.example .env
php artisan key:generate
# edit .env to set DB_* MySQL credentials
php artisan migrate --seed
php artisan storage:link
```

## Terminal 1 — Laravel API

```bash
cd backend
php artisan serve --host=127.0.0.1 --port=8010
```

API base: http://127.0.0.1:8010/api/v1

## Terminal 2 — Queue worker

```bash
cd backend
php artisan queue:work --tries=3
```

## Terminal 3 — Reverb (optional, off by default)

```bash
cd backend
php artisan reverb:start --host=127.0.0.1 --port=8080
```

## Terminal 4 — Flutter frontend

```bash
cd frontend
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 8090 \
  --dart-define=MCARE_USE_BACKEND=true \
  --dart-define=MCARE_API_URL=http://127.0.0.1:8010/api/v1
```

If you enable Reverb, also add: `--dart-define=MCARE_WS_URL=ws://127.0.0.1:8080`

## Demo accounts

After `php artisan migrate --seed`, use password **`demo-password`** for every account:

| Email | Role | Password |
|---|---|---|
| `admin@mcare.health` | Administrator | `demo-password` |
| `assistant@mcare.health` | mCare Assistant (all seeded grants) | `demo-password` |
| `dr.mensah@mcare.health` | Doctor (Internal medicine) | `demo-password` |
| `dr.adeyemi@mcare.health` | Doctor (Endocrinology) | `demo-password` |
| `dr.kamau@mcare.health` | Pending doctor approval | `demo-password` |
| `dr.wanjiru@mcare.health` | Pending doctor approval | `demo-password` |
| `amara.okonkwo@example.com` | Patient — rich demonstration chart | `demo-password` |
| `brian.otieno@example.com` | Patient — stable asthma | `demo-password` |
| `wangari.njeri@example.com` | Patient — post-stroke/critical | `demo-password` |
| `daniel.mwangi@example.com` | Patient — wellness monitoring | `demo-password` |
| `esther.wambui@example.com` | Patient — hypertension/warning | `demo-password` |
|---|---|
| `admin@mcare.health` | Administrator |
| `assistant@mcare.health` | mCare Assistant (all seeded grants) |
| `dr.mensah@mcare.health` | Doctor (Internal medicine) |
| `dr.adeyemi@mcare.health` | Doctor (Endocrinology) |
| `dr.kamau@mcare.health` | Pending doctor approval |
| `dr.wanjiru@mcare.health` | Pending doctor approval |
| `amara.okonkwo@example.com` | Patient — rich demonstration chart |
| `brian.otieno@example.com` | Patient — stable asthma |
| `wangari.njeri@example.com` | Patient — post-stroke/critical |
| `daniel.mwangi@example.com` | Patient — wellness monitoring |
| `esther.wambui@example.com` | Patient — hypertension/warning |
