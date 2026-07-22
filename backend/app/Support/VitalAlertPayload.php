<?php

namespace App\Support;

use App\Models\AppNotification;
use App\Models\VitalReading;

/**
 * Unified vital alert title/body formatting and vital_key inference.
 */
class VitalAlertPayload
{
    public static function forReading(VitalReading $reading): array
    {
        $label = VitalLabels::label($reading->vital_key);
        $display = self::formatValue($reading);
        $time = $reading->recorded_at?->format('g:i A') ?? 'now';

        $rangeHint = match ($reading->risk) {
            'critical' => 'critically outside your target range',
            'warning' => 'above your target range',
            default => 'outside your target range',
        };

        $title = match ($reading->risk) {
            'critical' => self::criticalTitle($reading->vital_key, $label),
            default => self::warningTitle($reading->vital_key, $label),
        };

        return [
            'title' => $title,
            'body' => "$display recorded at $time — $rangeHint.",
        ];
    }

    public static function vitalKeyFromNotification(AppNotification $n): ?string
    {
        $args = $n->action_arguments;
        if (is_array($args) && ! empty($args['vital_key'])) {
            return (string) $args['vital_key'];
        }

        return self::inferFromText(($n->title ?? '').' '.($n->body ?? ''));
    }

    public static function valueFromNotification(AppNotification $n): ?string
    {
        $args = $n->action_arguments;
        if (is_array($args) && isset($args['value'])) {
            $vitalKey = $args['vital_key'] ?? null;
            $unit = $vitalKey ? VitalLabels::unit((string) $vitalKey) : '';
            $formatted = self::formatScalar((float) $args['value'], (string) $vitalKey);
            return $unit !== '' ? "$formatted $unit" : $formatted;
        }

        return $n->body;
    }

    public static function alertToApiArray(AppNotification $n, array $extra = []): array
    {
        return array_merge([
            'id' => (string) $n->id,
            'kind' => $n->kind,
            'title' => $n->title,
            'body' => $n->body,
            'vital_key' => self::vitalKeyFromNotification($n),
            'value' => self::valueFromNotification($n),
            'severity' => $n->kind === 'vital_critical' || $n->kind === 'sos'
                ? 'critical'
                : 'warning',
            'acknowledged' => $n->read,
            'resolved' => $n->resolved,
            'resolution_action' => is_array($n->action_arguments)
                ? ($n->action_arguments['resolution_action'] ?? null)
                : null,
            'resolution_note' => is_array($n->action_arguments)
                ? ($n->action_arguments['resolution_note'] ?? null)
                : null,
            'resolution_custom_action' => is_array($n->action_arguments)
                ? ($n->action_arguments['resolution_custom_action'] ?? null)
                : null,
            'created_at' => $n->created_at?->toIso8601String(),
        ], $extra);
    }

    private static function criticalTitle(string $vitalKey, string $label): string
    {
        return match ($vitalKey) {
            'bloodGlucose' => 'Blood glucose is critical',
            'heartRate' => 'Heart rate is critical',
            'bloodOxygen' => 'Blood oxygen is critical',
            default => "$label is critical",
        };
    }

    private static function warningTitle(string $vitalKey, string $label): string
    {
        return match ($vitalKey) {
            'bloodGlucose' => 'Blood glucose is high',
            'heartRate' => 'Heart rate elevated',
            'bloodOxygen' => 'Blood oxygen low',
            default => "$label out of range",
        };
    }

    private static function formatValue(VitalReading $reading): string
    {
        if ($reading->vital_key === 'bloodPressure' && $reading->secondary_value !== null) {
            return sprintf(
                '%d/%d mmHg',
                (int) round($reading->value),
                (int) round($reading->secondary_value)
            );
        }

        $unit = VitalLabels::unit($reading->vital_key);
        $formatted = self::formatScalar($reading->value, $reading->vital_key);

        return $unit !== '' ? "$formatted $unit" : $formatted;
    }

    private static function formatScalar(float $value, string $vitalKey): string
    {
        if (in_array($vitalKey, ['temperature', 'weight'], true)) {
            return number_format($value, 1, '.', '');
        }

        return (string) (int) round($value);
    }

    private static function inferFromText(string $text): ?string
    {
        $lower = strtolower($text);
        if (str_contains($lower, 'glucose') || str_contains($lower, 'mg/dl')) {
            return 'bloodGlucose';
        }
        if (str_contains($lower, 'heart') || str_contains($lower, 'bpm')) {
            return 'heartRate';
        }
        if (str_contains($lower, 'oxygen') || str_contains($lower, 'spo')) {
            return 'bloodOxygen';
        }
        if (str_contains($lower, 'temp') || str_contains($lower, '°c')) {
            return 'temperature';
        }
        if (str_contains($lower, 'resp') || str_contains($lower, '/min')) {
            return 'respiratoryRate';
        }
        if (str_contains($lower, 'weight') || str_contains($lower, 'kg')) {
            return 'weight';
        }
        if (str_contains($lower, 'pressure') || str_contains($lower, 'mmhg')) {
            return 'bloodPressure';
        }

        return null;
    }
}
