<?php

namespace App\Support;

/**
 * Catalogue of the sections an admin can tick when issuing a patient report.
 *
 * Confidentiality model: a section is either `open` (administrative facts the
 * patient already shares with staff to receive care) or `restricted` (clinical
 * detail or personally-identifying contact data). Ticking ANY restricted
 * section makes the whole request consent-gated — the patient must approve it
 * with an OTP or the approval link before the report can be assembled.
 *
 * Clinical sections additionally force a doctor signature on the finished
 * report; an administrative-only report can be issued without one.
 */
class PatientReportSections
{
    public const OPEN = 'open';

    public const RESTRICTED = 'restricted';

    /**
     * key => [label, description, group, sensitivity, clinical]
     */
    public const CATALOG = [
        'identity' => [
            'label' => 'Name & patient ID',
            'description' => 'Full name, mCare patient ID, and account status.',
            'group' => 'Personal',
            'sensitivity' => self::OPEN,
            'clinical' => false,
        ],
        'demographics' => [
            'label' => 'Demographics',
            'description' => 'Age, date of birth, gender, and blood type.',
            'group' => 'Personal',
            'sensitivity' => self::RESTRICTED,
            'clinical' => false,
        ],
        'contact' => [
            'label' => 'Contact details',
            'description' => 'Email address and phone number.',
            'group' => 'Personal',
            'sensitivity' => self::RESTRICTED,
            'clinical' => false,
        ],
        'address' => [
            'label' => 'Home address',
            'description' => 'Residential address on file.',
            'group' => 'Personal',
            'sensitivity' => self::RESTRICTED,
            'clinical' => false,
        ],
        'next_of_kin' => [
            'label' => 'Next of kin & emergency contacts',
            'description' => 'Names, relationships, phone numbers, and emails.',
            'group' => 'Personal',
            'sensitivity' => self::RESTRICTED,
            'clinical' => false,
        ],
        'account' => [
            'label' => 'Account & login history',
            'description' => 'Registration date, approval trail, and sign-in activity.',
            'group' => 'Account',
            'sensitivity' => self::RESTRICTED,
            'clinical' => false,
        ],
        'care_team' => [
            'label' => 'Care team',
            'description' => 'Assigned doctors and their roles.',
            'group' => 'Care',
            'sensitivity' => self::OPEN,
            'clinical' => false,
        ],
        'health_profile' => [
            'label' => 'Health profile',
            'description' => 'Chronic conditions, allergies, height, weight, and BMI.',
            'group' => 'Clinical',
            'sensitivity' => self::RESTRICTED,
            'clinical' => true,
        ],
        'vitals_summary' => [
            'label' => 'Vitals summary',
            'description' => 'Latest reading and 30-day trend per assigned vital.',
            'group' => 'Clinical',
            'sensitivity' => self::RESTRICTED,
            'clinical' => true,
        ],
        'vitals_readings' => [
            'label' => 'Full vitals log',
            'description' => 'Every recorded reading with timestamps and risk bands.',
            'group' => 'Clinical',
            'sensitivity' => self::RESTRICTED,
            'clinical' => true,
        ],
        'medications' => [
            'label' => 'Medications & prescriptions',
            'description' => 'Active and past medication with prescriber details.',
            'group' => 'Clinical',
            'sensitivity' => self::RESTRICTED,
            'clinical' => true,
        ],
        'adherence' => [
            'label' => 'Medication adherence',
            'description' => 'Dose-taking record and adherence percentage.',
            'group' => 'Clinical',
            'sensitivity' => self::RESTRICTED,
            'clinical' => true,
        ],
        'meal_plans' => [
            'label' => 'Meal plans & nutrition',
            'description' => 'Assigned meals with macros and prescriber notes.',
            'group' => 'Clinical',
            'sensitivity' => self::RESTRICTED,
            'clinical' => true,
        ],
        'appointments' => [
            'label' => 'Appointments',
            'description' => 'Scheduled, completed, and cancelled consultations.',
            'group' => 'Clinical',
            'sensitivity' => self::RESTRICTED,
            'clinical' => true,
        ],
        'alerts' => [
            'label' => 'Vital alerts',
            'description' => 'Warning and critical alerts raised for this patient.',
            'group' => 'Clinical',
            'sensitivity' => self::RESTRICTED,
            'clinical' => true,
        ],
        'sos' => [
            'label' => 'Emergency (SOS) events',
            'description' => 'SOS triggers, locations, and responder outcomes.',
            'group' => 'Clinical',
            'sensitivity' => self::RESTRICTED,
            'clinical' => true,
        ],
        'documents' => [
            'label' => 'Medical documents',
            'description' => 'Index of uploaded documents (titles and dates only).',
            'group' => 'Clinical',
            'sensitivity' => self::RESTRICTED,
            'clinical' => true,
        ],
        'notes' => [
            'label' => 'Clinical notes & reports',
            'description' => 'Doctor-authored reports published to the record.',
            'group' => 'Clinical',
            'sensitivity' => self::RESTRICTED,
            'clinical' => true,
        ],
        'progress' => [
            'label' => 'Progress & engagement',
            'description' => 'Logging streak, activity counts, and engagement score.',
            'group' => 'Clinical',
            'sensitivity' => self::RESTRICTED,
            'clinical' => true,
        ],
    ];

    /** @return list<string> */
    public static function keys(): array
    {
        return array_keys(self::CATALOG);
    }

    public static function exists(string $key): bool
    {
        return array_key_exists($key, self::CATALOG);
    }

    /**
     * Catalogue shaped for the client's tick-list UI.
     *
     * @return list<array<string, mixed>>
     */
    public static function toApiArray(): array
    {
        $out = [];
        foreach (self::CATALOG as $key => $meta) {
            $out[] = [
                'key' => $key,
                'label' => $meta['label'],
                'description' => $meta['description'],
                'group' => $meta['group'],
                'sensitivity' => $meta['sensitivity'],
                'clinical' => $meta['clinical'],
                'requires_consent' => $meta['sensitivity'] === self::RESTRICTED,
            ];
        }

        return $out;
    }

    /**
     * True when any ticked section is restricted — the patient must consent.
     *
     * @param  list<string>  $sections
     */
    public static function requiresConsent(array $sections): bool
    {
        foreach ($sections as $key) {
            if ((self::CATALOG[$key]['sensitivity'] ?? self::RESTRICTED) === self::RESTRICTED) {
                return true;
            }
        }

        return false;
    }

    /**
     * True when any ticked section carries clinical content — a doctor must
     * sign the report before it can be issued.
     *
     * @param  list<string>  $sections
     */
    public static function requiresSignature(array $sections): bool
    {
        foreach ($sections as $key) {
            if (self::CATALOG[$key]['clinical'] ?? false) {
                return true;
            }
        }

        return false;
    }

    public static function label(string $key): string
    {
        return self::CATALOG[$key]['label'] ?? $key;
    }

    /**
     * Human-readable list used in consent messages so the patient knows
     * exactly what they are approving.
     *
     * @param  list<string>  $sections
     */
    public static function labelList(array $sections): string
    {
        $labels = array_map(fn (string $k) => self::label($k), $sections);

        return implode(', ', $labels);
    }
}
