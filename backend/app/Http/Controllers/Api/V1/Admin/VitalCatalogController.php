<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\VitalCatalog;
use App\Services\AuditService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class VitalCatalogController extends Controller
{
    use ApiResponse;

    public function __construct(private readonly AuditService $audit) {}

    public function index()
    {
        $entries = VitalCatalog::orderBy('vital_key')
            ->get()
            ->map(fn (VitalCatalog $v) => $v->toApiArray());

        return $this->success(['vital_catalog' => $entries]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'label' => 'required|string|max:80',
            'unit' => 'required|string|max:24',
            'normal_min' => 'required|numeric',
            'normal_max' => 'required|numeric|gte:normal_min',
            'warning_low' => 'required|numeric',
            'warning_high' => 'required|numeric',
            'critical_low' => 'required|numeric',
            'critical_high' => 'required|numeric',
            'description' => 'nullable|string|max:280',
            'enabled' => 'sometimes|boolean',
        ]);

        $key = 'custom_'.Str::lower(Str::slug($data['label'], '_'));
        if (VitalCatalog::where('vital_key', $key)->exists()) {
            $key .= '_'.Str::lower(Str::random(4));
        }

        $entry = VitalCatalog::create([
            'vital_key'    => $key,
            'label'        => $data['label'],
            'unit'         => $data['unit'],
            'description'  => $data['description'] ?? null,
            'normal_min'   => $data['normal_min'],
            'normal_max'   => $data['normal_max'],
            'warning_low'  => $data['warning_low'],
            'warning_high' => $data['warning_high'],
            'critical_low' => $data['critical_low'],
            'critical_high'=> $data['critical_high'],
            'enabled'      => $data['enabled'] ?? true,
        ]);

        $this->audit->record(
            $request->user(),
            'vital_catalog.created',
            $data['label'],
            'activity',
            ['vital_key' => $key],
        );

        return $this->success(['entry' => $entry->toApiArray()], 'Vital added.', 201);
    }

    public function update(Request $request, VitalCatalog $vitalCatalog)
    {
        $data = $request->validate([
            'normal_min' => 'sometimes|numeric',
            'normal_max' => 'sometimes|numeric',
            'warning_low' => 'sometimes|numeric',
            'warning_high' => 'sometimes|numeric',
            'critical_low' => 'sometimes|numeric',
            'critical_high' => 'sometimes|numeric',
            'enabled' => 'sometimes|boolean',
            'label' => 'nullable|string|max:80',
            'unit' => 'nullable|string|max:24',
            'description' => 'nullable|string|max:280',
        ]);

        $vitalCatalog->update(collect($data)->only([
            'label', 'unit', 'description',
            'normal_min', 'normal_max', 'warning_low', 'warning_high',
            'critical_low', 'critical_high', 'enabled',
        ])->filter(fn ($v) => $v !== null)->all());

        $this->audit->record(
            $request->user(),
            'vital_catalog.updated',
            $vitalCatalog->vital_key,
            'activity',
        );

        return $this->success(['entry' => $vitalCatalog->fresh()->toApiArray()], 'Vital updated.');
    }

    public function destroy(Request $request, VitalCatalog $vitalCatalog)
    {
        if (! str_starts_with($vitalCatalog->vital_key, 'custom_')) {
            return $this->error('Built-in vitals cannot be deleted — disable instead.', 422);
        }

        $key = $vitalCatalog->vital_key;
        $vitalCatalog->delete();

        $this->audit->record(
            $request->user(),
            'vital_catalog.deleted',
            $key,
            'activity',
        );

        return $this->success(null, 'Custom vital removed.');
    }
}
