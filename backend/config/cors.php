<?php

return [
    'paths' => ['api/*', 'broadcasting/auth', 'sanctum/csrf-cookie'],
    'allowed_methods' => ['*'],
    'allowed_origins' => [
        // Production (matendocare.com)
        'https://app.matendocare.com',
        'https://matendocare.com',
        'https://www.matendocare.com',
        // Local development
        'http://localhost:8090',
        'http://127.0.0.1:8090',
        'http://0.0.0.0:8090',
    ],
    'allowed_origins_patterns' => [],
    'allowed_headers' => ['*'],
    'exposed_headers' => [],
    'max_age' => 0,
    'supports_credentials' => false,
];
