<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class VitalCatalog extends Model
{
    protected $table = 'vital_catalog';

    protected $fillable = [
        'vital_key',
        'label',
        'unit',
        'description',
        'normal_min',
        'normal_max',
        'warning_low',
        'warning_high',
        'critical_low',
        'critical_high',
        'enabled',
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
            'enabled' => 'boolean',
        ];
    }

    public function toApiArray(): array
    {
        return [
            'id'           => (string) $this->id,
            'vital'        => $this->vital_key,
            'vital_key'    => $this->vital_key,
            'custom_label' => $this->label,
            'custom_unit'  => $this->unit,
            'description'  => $this->description,
            'normal_min'   => $this->normal_min,
            'normal_max'   => $this->normal_max,
            'warning_low'  => $this->warning_low,
            'warning_high' => $this->warning_high,
            'critical_low' => $this->critical_low,
            'critical_high'=> $this->critical_high,
            'enabled'      => $this->enabled,
            'created_by'   => 'system',
            'created_at'   => $this->created_at?->toIso8601String(),
            'updated_at'   => $this->updated_at?->toIso8601String(),
        ];
    }
}
