<?php

namespace App\Observers;

use App\Services\RealtimeSignalService;
use Illuminate\Database\Eloquent\Model;

/**
 * Application-level data trigger for real-time invalidation signals.
 *
 * Keeping this in the application layer makes the behaviour portable across
 * MySQL, MariaDB and SQLite tests and keeps database triggers free of network
 * side effects.
 */
class RealtimeModelObserver
{
    public function created(Model $model): void
    {
        RealtimeSignalService::forModel($model, 'created');
    }

    public function updated(Model $model): void
    {
        RealtimeSignalService::forModel($model, 'updated');
    }

    public function deleted(Model $model): void
    {
        RealtimeSignalService::forModel($model, 'deleted');
    }

    public function restored(Model $model): void
    {
        RealtimeSignalService::forModel($model, 'restored');
    }
}
