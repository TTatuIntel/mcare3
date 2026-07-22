<?php

namespace App\Support;

/**
 * Human-readable labels for built-in vital keys.
 */
class VitalLabels
{
    private const LABELS = [
        'bloodPressure' => 'Blood Pressure',
        'heartRate' => 'Heart Rate',
        'bloodOxygen' => 'Blood Oxygen',
        'temperature' => 'Temperature',
        'bloodGlucose' => 'Blood Glucose',
        'respiratoryRate' => 'Respiratory Rate',
        'weight' => 'Weight',
    ];

    public static function label(string $vitalKey): string
    {
        return self::LABELS[$vitalKey] ?? ucfirst($vitalKey);
    }

    public static function unit(string $vitalKey): string
    {
        return match ($vitalKey) {
            'bloodPressure' => 'mmHg',
            'heartRate' => 'bpm',
            'bloodOxygen' => '%',
            'temperature' => '°C',
            'bloodGlucose' => 'mg/dL',
            'respiratoryRate' => '/min',
            'weight' => 'kg',
            default => '',
        };
    }
}
