<?php

return [
    /*
     * The frontend documentation portal. It exists only where a token was deliberately
     * placed in .env AND the application runs as one of the environments below.
     * Production is never in that list, so on production the routes are not registered
     * at all: a request gets the ordinary 404 rather than a 403 that would confirm the
     * page is there. Both conditions must hold — a token leaked into a production .env
     * still does not open the portal.
     */
    'token' => env('DEV_DOCS_TOKEN'),

    'environments' => array_values(array_filter(array_map(
        'trim',
        explode(',', (string) env('DEV_DOCS_ENVS', 'local,development,staging,testing'))
    ))),

    // Documentation root, relative to the project base path.
    'root' => 'docs/ai',

    /*
     * Display order and titles of the sections the features are grouped into. The `area`
     * key in each document's front-matter points here.
     *
     * REPLACE THESE WITH THIS PROJECT'S OWN SECTIONS. They are the reader's map of the
     * system, so they should read the way the people who work on it talk about it — a
     * storefront and a back-office CRM do not share a vocabulary. A document filed under
     * a section that is missing here still renders, under its own slug in Latin; the test
     * `test_every_section_a_document_names_has_a_title_in_the_config` fails when that
     * happens, which is the only thing that catches it.
     */
    'areas' => [
        'core' => 'Основне',
        'platform' => 'Платформа',
    ],
];
