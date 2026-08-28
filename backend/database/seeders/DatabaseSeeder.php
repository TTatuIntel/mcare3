<?php

namespace Database\Seeders;

use App\Services\RealtimeSignalService;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        if (app()->environment('production') && ! config('mcare.allow_demo_seed')) {
            throw new \RuntimeException(
                'Synthetic mCare data is blocked in production. Set MCARE_ALLOW_DEMO_SEED=true only for an isolated non-live environment.',
            );
        }

        // Seeding installs one coherent snapshot. Broadcasting hundreds of
        // row-level invalidations while no client can safely consume an
        // incomplete snapshot only fills the queue. Real application writes
        // and `mcare:simulate` remain fully observed after this closure.
        RealtimeSignalService::withoutSignals(function (): void {
            $this->call([
                VitalCatalogSeeder::class,      // vital type catalog and clinical ranges
                SystemSettingsSeeder::class,    // platform toggle settings
                StaffSeeder::class,             // admin, assistant, doctors, pending applicants
                PatientSeeder::class,           // primary patient + complete clinical history
                PatientCaseloadSeeder::class,   // four additional patient risk profiles
                AdminDemoSeeder::class,         // operational queues and decision trails
                WorkflowDemoSeeder::class,      // every durable workflow and every active role
            ]);
        });
    }
}
