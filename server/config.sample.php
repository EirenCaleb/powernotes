<?php
// PowerNotes server config.
// Copy this file to ONE folder above public_html, named powernotes_config.php:
//   /home/<user>/domains/<domain>/powernotes_config.php
// so it can never be downloaded from the web. Never commit the real file.

return [
    'db_host' => 'localhost',
    'db_name' => 'u000000000_powernotes',
    'db_user' => 'u000000000_powernotes',
    'db_pass' => 'CHANGE_ME',

    // Public address of this server folder, no trailing slash.
    // Used to build share links, e.g. https://notes.example.com
    'base_url' => 'https://notes.example.com',

    // Gemini API key for AI, OCR and transcription (https://aistudio.google.com/apikey).
    'gemini_key' => '',
    'gemini_model' => 'gemini-2.5-flash',

    // The first account can always be created. Set true to allow more sign-ups.
    'allow_register' => false,

    // true returns error details in JSON. Keep false in production.
    'debug' => false,
];
