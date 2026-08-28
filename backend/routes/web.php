<?php

use App\Support\ProductionReadiness;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});


// `/up` is Laravel's process liveness check. `/ready` additionally verifies
// dependencies required before a load balancer should route traffic here.
Route::get('/ready', function () {
    $readiness = ProductionReadiness::runtime();

    return response()->json([
        'status' => $readiness['ready'] ? 'ready' : 'not_ready',
        'checks' => $readiness['checks'],
        'checked_at' => now()->toIso8601String(),
    ], $readiness['ready'] ? 200 : 503);
});
