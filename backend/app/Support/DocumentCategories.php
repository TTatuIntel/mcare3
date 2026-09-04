<?php

namespace App\Support;

/**
 * The one list of document categories.
 *
 * The keys are camelCase because they are the names of a Dart enum in the
 * Flutter app — they travel over the wire unchanged and must not be
 * prettified here. They were previously written out by hand in three
 * validation rules and a match arm, which is how `vitalReport` could be filed
 * by the server and then rejected the moment anyone tried to edit the same
 * document.
 */
final class DocumentCategories
{
    /** @var array<string, string> key => label shown to patients */
    private const LABELS = [
        'labResult' => 'lab result',
        'prescription' => 'prescription',
        'imaging' => 'imaging',
        'discharge' => 'discharge summary',
        'consultationNote' => 'consultation note',
        // Issued by the care team from a patient's vital report request.
        'vitalReport' => 'vital report',
        // A customised report issued from the record — the patient's own copy
        // of a disclosure that went to a third party. Filed as 'other' until
        // now, which buried the one document a patient is most likely to come
        // looking for by name among their insurance scans.
        'report' => 'medical report',
        'referral' => 'referral letter',
        'insurance' => 'insurance or claim form',
        'other' => 'document',
    ];

    /** @return list<string> */
    public static function keys(): array
    {
        return array_keys(self::LABELS);
    }

    /** The `in:` rule body for a validator. */
    public static function rule(): string
    {
        return implode(',', self::keys());
    }

    public static function exists(?string $key): bool
    {
        return $key !== null && array_key_exists($key, self::LABELS);
    }

    /** A patient should never be shown "consultationNote". */
    public static function label(?string $key): string
    {
        return self::LABELS[$key] ?? 'document';
    }
}
