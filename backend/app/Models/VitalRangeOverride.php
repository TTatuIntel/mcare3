<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class VitalRangeOverride extends Model
{
    protected $fillable = [
        'user_id',
        'vital_key',
        'normal_min',
        'normal_max',
        'warning_low',
        'warning_high',
        'critical_low',
        'critical_high',
        'set_by_user_id',
    ];

    protected function casts(): array
    {
        return [
            'normal_min' => 'float',
            'normal_max' => 'float',
            'warning_low' => 'float',
            'warning_high' => 'float',
            'critical_low' => 'float',
            'critical_high' => 'float',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function setBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'set_by_user_id');
    }
}
