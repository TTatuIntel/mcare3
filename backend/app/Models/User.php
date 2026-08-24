<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable;

    public const MAX_FAILED_LOGINS = 5;

    public const LOCKOUT_MINUTES = 30;

    protected $fillable = [
        'unique_id',
        'first_name',
        'last_name',
        'email',
        'phone',
        'role',
        'specialty',
        'license_number',
        'avatar_path',
        'credential_document_path',
        'credential_document_name',
        'approval_status',
        'google_id',
        'apple_id',
        'password',
        'email_verified_at',
        'failed_login_attempts',
        'locked_until',
        'must_change_password',
        'last_login_at',
        'last_login_ip',
        'login_count',
        'approved_at',
        'approved_by',
        'approval_note',
        'rejected_at',
        'rejection_reason',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'locked_until' => 'datetime',
            'must_change_password' => 'boolean',
            'password' => 'hashed',
            'last_login_at' => 'datetime',
            'approved_at' => 'datetime',
            'rejected_at' => 'datetime',
        ];
    }

    /**
     * Staff member who approved this account's application. Null for
     * self-serve patient registrations and for accounts approved before the
     * decision trail existed (audit log remains the fallback there).
     */
    public function approvedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'approved_by');
    }

    /**
     * Record a successful sign-in. Called from the single auth funnel so
     * password, OTP, Google, and Apple sign-ins all update the same trail.
     */
    public function recordLogin(?string $ip = null): void
    {
        $this->forceFill([
            'last_login_at' => now(),
            'last_login_ip' => $ip,
            'login_count' => (int) $this->login_count + 1,
        ])->save();
    }

    public function reportRequests(): HasMany
    {
        return $this->hasMany(PatientReportRequest::class, 'patient_user_id');
    }

    public function isLocked(): bool
    {
        return $this->locked_until !== null && $this->locked_until->isFuture();
    }

    public function clearLockout(): void
    {
        $this->forceFill([
            'failed_login_attempts' => 0,
            'locked_until' => null,
        ])->save();
    }

    public function registerFailedLogin(): void
    {
        $attempts = (int) $this->failed_login_attempts + 1;
        $updates = ['failed_login_attempts' => $attempts];
        if ($attempts >= self::MAX_FAILED_LOGINS) {
            $updates['locked_until'] = now()->addMinutes(self::LOCKOUT_MINUTES);
        }
        $this->forceFill($updates)->save();
    }

    public function healthProfile(): HasOne
    {
        return $this->hasOne(PatientHealthProfile::class);
    }

    public function emergencyContacts(): HasMany
    {
        return $this->hasMany(EmergencyContact::class);
    }

    public function assignedVitals(): HasMany
    {
        return $this->hasMany(PatientAssignedVital::class);
    }

    public function trackedVitals(): HasMany
    {
        return $this->hasMany(PatientTrackedVital::class);
    }

    public function vitalReadings(): HasMany
    {
        return $this->hasMany(VitalReading::class);
    }

    public function vitalRangeOverrides(): HasMany
    {
        return $this->hasMany(VitalRangeOverride::class);
    }

    public function medications(): HasMany
    {
        return $this->hasMany(Medication::class);
    }

    public function medicationDoses(): HasMany
    {
        return $this->hasMany(MedicationDose::class);
    }

    public function appointments(): HasMany
    {
        return $this->hasMany(Appointment::class);
    }

    public function medicalDocuments(): HasMany
    {
        return $this->hasMany(MedicalDocument::class);
    }

    public function conversations(): HasMany
    {
        return $this->hasMany(Conversation::class);
    }

    public function appNotifications(): HasMany
    {
        return $this->hasMany(AppNotification::class);
    }

    public function supportTickets(): HasMany
    {
        return $this->hasMany(SupportTicket::class);
    }

    public function sosEvents(): HasMany
    {
        return $this->hasMany(SosEvent::class);
    }

    public function careRequests(): HasMany
    {
        return $this->hasMany(CareRequest::class);
    }

    public function careAssignments(): HasMany
    {
        return $this->hasMany(CareAssignment::class, 'patient_user_id');
    }

    public function vitalReportRequests(): HasMany
    {
        return $this->hasMany(VitalReportRequest::class);
    }

    public function assistantPermissions(): HasMany
    {
        return $this->hasMany(AssistantPermission::class);
    }

    public function fcmTokens(): HasMany
    {
        return $this->hasMany(FcmToken::class);
    }

    public function settings(): HasOne
    {
        return $this->hasOne(UserSetting::class);
    }

    public function staffNotificationStates(): HasMany
    {
        return $this->hasMany(StaffNotificationState::class);
    }

    public function hasAssistantPermission(string $key): bool
    {
        if ($this->role === 'admin') {
            return true;
        }
        if ($this->role !== 'mcare_assistant') {
            return false;
        }
        return $this->assistantPermissions()
            ->where('permission_key', $key)
            ->exists();
    }

    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'unique_id' => $this->unique_id,
            'first_name' => $this->first_name,
            'last_name' => $this->last_name,
            'email' => $this->email,
            'phone' => $this->phone,
            'role' => $this->roleToClient(),
            'specialty' => $this->specialty,
            'license_number' => $this->license_number,
            'avatar_url' => $this->avatarUrl(),
            'approval_status' => $this->approvalStatusToClient(),
            'email_verified' => $this->email_verified_at !== null,
            'profile_complete' => $this->isProfileComplete(),
            'must_change_password' => (bool) $this->must_change_password,
            'is_locked' => $this->isLocked(),
            'locked_until' => $this->locked_until?->toIso8601String(),
            'failed_login_attempts' => (int) $this->failed_login_attempts,
            'created_at' => $this->created_at?->toIso8601String(),
            // Lifecycle trail — additive, so existing consumers are unaffected.
            'email_verified_at' => $this->email_verified_at?->toIso8601String(),
            'last_login_at' => $this->last_login_at?->toIso8601String(),
            'login_count' => (int) $this->login_count,
            'approved_at' => $this->approved_at?->toIso8601String(),
            'rejected_at' => $this->rejected_at?->toIso8601String(),
            'has_credential_document' => $this->credential_document_path !== null,
        ];
    }

    public function avatarUrl(): ?string
    {
        if (! $this->avatar_path) {
            return null;
        }
        $url = \Illuminate\Support\Facades\Storage::disk('public')->url($this->avatar_path);

        return \Illuminate\Support\Str::startsWith($url, ['http://', 'https://'])
            ? $url
            : url($url);
    }

    public function isProfileComplete(): bool
    {
        $phone = trim((string) ($this->phone ?? ''));

        return trim($this->first_name) !== ''
            && trim($this->last_name) !== ''
            && strlen($phone) >= 7;
    }

    public function roleToClient(): string
    {
        return match ($this->role) {
            'mcare_assistant' => 'mcareAssistant',
            default => $this->role,
        };
    }

    public function approvalStatusToClient(): string
    {
        return match ($this->approval_status) {
            'pending_approval' => 'pendingApproval',
            default => $this->approval_status,
        };
    }

    public static function generateUniqueId(): string
    {
        return 'MCR-'.str_pad((string) random_int(1, 999999), 6, '0', STR_PAD_LEFT);
    }

    public function fullName(): string
    {
        return trim($this->first_name.' '.$this->last_name);
    }
}
