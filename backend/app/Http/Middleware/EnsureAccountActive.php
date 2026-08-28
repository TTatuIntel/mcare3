<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Rejects authenticated sessions as soon as an account leaves the active
 * state. This protects every API and broadcast route even if status was
 * changed outside the normal controller path.
 */
class EnsureAccountActive
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if ($user && $user->approval_status !== 'active') {
            if (in_array($user->approval_status, ['suspended', 'rejected'], true)) {
                $user->tokens()->delete();
            }

            return response()->json([
                'success' => false,
                'data' => ['account_status' => $user->approvalStatusToClient()],
                'message' => 'This account is not active.',
            ], 403);
        }

        return $next($request);
    }
}
