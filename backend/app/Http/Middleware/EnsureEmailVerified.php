<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureEmailVerified
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if ($user && $user->email_verified_at === null) {
            return response()->json([
                'success' => false,
                'data' => ['verification_required' => true],
                'message' => 'Verify your email address before accessing mCare data.',
            ], 403);
        }

        return $next($request);
    }
}
