<?php

namespace Database\Seeders;

use App\Models\VitalCatalog;
use Illuminate\Database\Seeder;

/**
 * Default vital ranges (matches `VitalRanges.defaults` in
 * lib/shared/models/vital.dart). Only core types start enabled so
 * doctors can create/enable the rest via the app.
 */
class VitalCatalogSeeder extends Seeder
{
    public function run(): void
    {
        $defaults = [
            'bloodPressure'    => [90, 120, 80, 140, 70, 160],
            'heartRate'        => [60, 100, 50, 120, 40, 140],
            'bloodOxygen'      => [95, 100, 90, 100, 85, 100],
            'temperature'      => [36.1, 37.2, 35.5, 38.0, 35.0, 39.0],
            'bloodGlucose'     => [70, 100, 54, 126, 50, 180],
            'respiratoryRate' => [12, 20, 10, 24, 8, 28],
            'weight'           => [0, 500, 0, 500, 0, 500],
        ];

        $enabledByDefault = ['bloodPressure', 'bloodGlucose', 'heartRate'];

        foreach ($defaults as $vital => [$nMin, $nMax, $wLow, $wHigh, $cLow, $cHigh]) {
            VitalCatalog::updateOrCreate(
                ['vital_key' => $vital],
                [
                    'normal_min'    => $nMin,
                    'normal_max'    => $nMax,
                    'warning_low'   => $wLow,
                    'warning_high'  => $wHigh,
                    'critical_low'  => $cLow,
                    'critical_high' => $cHigh,
                    'enabled'       => in_array($vital, $enabledByDefault, true),
                ],
            );
        }
    }
}
