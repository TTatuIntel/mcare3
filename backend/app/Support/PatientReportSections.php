<?php

namespace App\Support;

/**
 * Catalogue of the sections an admin can tick when issuing a patient report.
 *
 * Confidentiality model: a section is either `open` (administrative facts the
 * patient already shares with staff to receive care) or `restricted` (clinical
 * detail or personally-identifying contact data), and separately either
 * clinical or not.
 *
 * Both are now presentation only — they tell the admin how sensitive a tick is
 * and let the UI group and badge accordingly. Neither decides a gate. Every
 * report takes the same route regardless of what is ticked: a nominated doctor
 * signs it, then an admin issues it. Deriving the gate from the selection meant
 * an administrative-only report could be issued with nobody having read it,
 * while a clinical one stalled behind a one-time code the patient rarely saw.
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
                // Named for what it is rather than what it used to trigger:
                // the tick-list badges it, nothing gates on it.
                'confidential' => $meta['sensitivity'] === self::RESTRICTED,
            ];
        }

        return $out;
    }

    /**
     * True when any ticked section carries clinical content.
     *
     * Informational: it drives the wording shown to the signing doctor, not
     * whether a signature is needed — every report needs one.
     *
     * @param  list<string>  $sections
     */
    public static function hasClinicalContent(array $sections): bool
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
     * Human-readable list, used wherever a person has to be told exactly which
     * parts of a record a report covers.
     *
     * @param  list<string>  $sections
     */
    public static function labelList(array $sections): string
    {
        $labels = array_map(fn (string $k) => self::label($k), $sections);

        return implode(', ', $labels);
    }
}
