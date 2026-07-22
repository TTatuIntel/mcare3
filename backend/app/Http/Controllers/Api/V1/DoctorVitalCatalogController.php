<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\V1\Admin\VitalCatalogController as AdminVitalCatalogController;
use App\Http\Controllers\Controller;
use App\Models\VitalCatalog;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * Doctors manage global vital templates (same rules as admin catalog writes).
 */
class DoctorVitalCatalogController extends Controller
{
    use ApiResponse;

    public function __construct(
        private readonly AdminVitalCatalogController $adminCatalog,
    ) {}

    public function index()
    {
        $entries = VitalCatalog::orderBy('vital_key')
            ->get()
            ->map->toApiArray()
            ->all();

        return $this->success(['vital_catalog' => $entries]);
    }

    public function store(Request $request)
    {
        return $this->adminCatalog->store($request);
    }

    public function update(Request $request, VitalCatalog $vitalCatalog)
    {
        return $this->adminCatalog->update($request, $vitalCatalog);
    }

    public function destroy(Request $request, VitalCatalog $vitalCatalog)
    {
        return $this->adminCatalog->destroy($request, $vitalCatalog);
    }
}
