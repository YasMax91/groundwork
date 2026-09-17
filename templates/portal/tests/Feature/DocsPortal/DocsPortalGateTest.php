<?php

namespace Tests\Feature\DocsPortal;

use App\Support\DocsPortal\DocsIndex;
use Tests\TestCase;

/**
 * The gate in front of the frontend documentation portal (config/docs_portal.php).
 *
 * The portal serves internal documentation — endpoint shapes, validation rules, which fields are
 * visible to whom — to a reader who has no account here. Two independent conditions therefore have
 * to hold before its routes are registered at all: a token deliberately placed in that environment's
 * .env, and an APP_ENV that is on the allowed list. Production is never on that list, so a token
 * copied into a production .env by accident still opens nothing, and the URL answers the ordinary
 * 404 rather than a 403 that would confirm the page is there.
 */
class DocsPortalGateTest extends TestCase
{
    public function test_the_portal_is_closed_without_a_token(): void
    {
        config(['docs_portal.token' => '']);

        $this->assertFalse(DocsIndex::isEnabled());
    }

    public function test_the_portal_is_closed_in_an_environment_that_is_not_allowed(): void
    {
        config([
            'docs_portal.token' => 'a-real-looking-token',
            'docs_portal.environments' => ['local', 'development', 'staging'],
        ]);

        $this->app->detectEnvironment(fn () => 'production');

        $this->assertFalse(DocsIndex::isEnabled());
    }

    public function test_production_is_not_in_the_shipped_list_of_allowed_environments(): void
    {
        $this->assertNotContains('production', config('docs_portal.environments'));
    }

    public function test_the_deployed_environments_are_allowed(): void
    {
        // The server .env templates set exactly these two — see .env.development.example and
        // .env.staging.example, which the servers are provisioned from.
        $this->assertContains('development', config('docs_portal.environments'));
        $this->assertContains('staging', config('docs_portal.environments'));
    }

    public function test_a_wrong_token_is_not_told_that_the_page_exists(): void
    {
        $this->get('/dev/docs/definitely-not-the-token')->assertNotFound();
    }
}
