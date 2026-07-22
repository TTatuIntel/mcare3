<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Gate a route on an mCare Assistant permission key. Admins bypass; assistants
 * are checked against the `assistant_permissions` pivot. All other roles are
 * rejected.
 *
 * Usage: ->middleware('permission:can_approve_healthworkers')
 */
class EnsurePermission
{
    public function handle(Request $request, Closure $next, string $key): Response
    {
        $user = $request->user();
        if (! $user) {
            return response()->json([
                'success' => false,
                'data' => null,
                'message' => 'Unauthenticated.',
            ], 401);
        }

        if ($user->role === 'admin') {
            return $next($request);
        }

        if ($user->role !== 'mcare_assistant' || ! $user->hasAssistantPermission($key)) {
            return response()->json([
                'success' => false,
                'data' => ['permission' => $key],
                'message' => 'Permission denied — required permission missing.',
            ], 403);
        }

        return $next($request);
    }
}
