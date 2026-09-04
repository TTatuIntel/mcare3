<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * One row of the live-change buffer written by [RealtimeSignalService].
 *
 * Deliberately not a record of anything: rows carry a channel, the client
 * data domains that changed, and what kind of thing changed — never a value,
 * a name, or a reading. They are pruned within minutes of being written.
 */
class RealtimeEvent extends Model
{
    protected $table = 'realtime_events';

    /** Rows are inserted once and never touched again. */
    public $timestamps = false;

    /** How long a client may be away and still catch up from the buffer. */
    public const RETENTION_MINUTES = 15;

    protected $fillable = [
        'channel',
        'domains',
        'action',
        'resource_type',
        'resource_id',
        'created_at',
    ];

    protected function casts(): array
    {
        return ['created_at' => 'datetime'];
    }

    /** @return list<string> */
    public function domainList(): array
    {
        return array_values(array_filter(explode(',', (string) $this->domains)));
    }
}
