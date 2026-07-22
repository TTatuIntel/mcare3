<?php

return [

    /*
    |--------------------------------------------------------------------------
    | mCare web app URL (Flutter frontend)
    | Used in invite emails and deep links.
    |--------------------------------------------------------------------------
    */
    'frontend_url' => rtrim((string) env('FRONTEND_URL', 'http://localhost:8090'), '/'),

];
