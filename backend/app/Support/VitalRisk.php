<?php

namespace App\Support;

/**
 * Shared vital risk assessment — used by VitalsController and seeders.
 */
class VitalRisk
{
    public static function assess(float $value, object $range): string
    {
        if ($value < $range->critical_low || $value > $range->critical_high) {
            return 'critical';
        }
        if ($value < $range->warning_low || $value > $range->warning_high) {
            return 'warning';
        }
        if ($value < $range->normal_min || $value > $range->normal_max) {
            return 'warning';
        }

        return 'normal';
    }
}
