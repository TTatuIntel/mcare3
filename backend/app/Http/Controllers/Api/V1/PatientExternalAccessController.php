<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\ExternalAccessLinkResource;
use App\Models\ExternalAccessToken;
use App\Support\ApiResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Patient-managed external access links/codes.
 *
 * A patient can generate a time-limited link (plus a short access code that
 * can be read out over the phone) so an external doctor — e.g. an emergency
 * physician — can view their record and add findings via the external portal.
 */
class PatientExternalAccessController extends Controller
{
    use ApiResponse;

    /** Characters that avoid 0/O and 1/I confusion when read aloud. */
    private const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

    public function index(Request $request)
    {
        $tokens = ExternalAccessToken::query()
            ->where('patient_user_id', $request->user()->id)
            ->orderByDesc('created_at')
            ->limit(20)
            ->get();

        return $this->success(['links' => ExternalAccessLinkResource::collection($tokens)]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'label' => 'nullable|string|max:120',
            'expires_in_hours' => 'nullable|integer|min:1|max:168', // up to 7 days
        ]);

        $user = $request->user();

        if (data_get($user->settings?->payload, 'privacy_allow_external_access') === false) {
            return $this->error(
                'External doctor access is disabled in your privacy settings.',
                403,
            );
        }

        // Cap concurrent active links so a lost phone can't mint unlimited access.
        $active = ExternalAccessToken::query()
            ->where('patient_user_id', $user->id)
            ->whereNull('revoked_at')
            ->where('expires_at', '>', now())
            ->count();
        if ($active >= 5) {
            return $this->error('You already have 5 active links. Revoke one before creating another.', 422);
        }

        // §4.1: audit + state change run in one transaction — compliance
        // requires the audit row not be droppable if the write succeeds.
        $token = DB::transaction(function () use ($user, $data) {
            $token = ExternalAccessToken::create([
                'patient_user_id' => $user->id,
                'created_by_user_id' => $user->id,
                'token' => Str::random(64),
                'access_code' => $this->generateAccessCode(),
                'label' => $data['label'] ?? 'Emergency access',
                'expires_at' => now()->addHours((int) ($data['expires_in_hours'] ?? 24)),
            ]);

            \App\Models\AuditEntry::create([
                'actor_user_id' => $user->id,
                'actor_label' => $user->fullName(),
                'action' => 'external.link_created',
                'target' => $user->fullName(),
                'category' => 'security',
                'meta' => ['token_id' => $token->id, 'expires_at' => $token->expires_at->toIso8601String()],
                'happened_at' => now(),
            ]);

            return $token;
        });

        return $this->success(
            ['link' => new ExternalAccessLinkResource($token)],
            'External access link created.',
            201,
        );
    }

    public function revoke(Request $request, ExternalAccessToken $externalToken)
    {
        if ((int) $externalToken->patient_user_id !== (int) $request->user()->id) {
            return $this->error('Not found.', 404);
        }

        if ($externalToken->revoked_at === null) {
            DB::transaction(function () use ($externalToken, $request) {
                $externalToken->update(['revoked_at' => now()]);

                \App\Models\AuditEntry::create([
                    'actor_user_id' => $request->user()->id,
                    'actor_label' => $request->user()->fullName(),
                    'action' => 'external.link_revoked',
                    'target' => $request->user()->fullName(),
                    'category' => 'security',
                    'meta' => ['token_id' => $externalToken->id],
                    'happened_at' => now(),
                ]);
            });
        }

        return $this->success(['link' => new ExternalAccessLinkResource($externalToken)], 'Link revoked.');
    }

    private function generateAccessCode(): string
    {
        do {
            $code = '';
            for ($i = 0; $i < 8; $i++) {
                $code .= self::CODE_ALPHABET[random_int(0, strlen(self::CODE_ALPHABET) - 1)];
            }
            // Grouped as XXXX-XXXX for readability.
            $code = substr($code, 0, 4).'-'.substr($code, 4);
        } while (ExternalAccessToken::where('access_code', $code)->exists());

        return $code;
    }
}
