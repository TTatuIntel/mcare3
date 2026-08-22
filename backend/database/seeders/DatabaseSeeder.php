<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $this->call([
            VitalCatalogSeeder::class,      // vital type catalog and clinical ranges
            SystemSettingsSeeder::class,    // platform toggle settings
            StaffSeeder::class,             // admin, assistant, doctors, pending applicants
            PatientSeeder::class,           // primary patient (Amara Okonkwo) + full clinical dataset
            PatientCaseloadSeeder::class,   // four additional patients across both doctors
            AdminDemoSeeder::class,         // support tickets, care requests, fresh audit, extra SOS
        ]);
    }
}
