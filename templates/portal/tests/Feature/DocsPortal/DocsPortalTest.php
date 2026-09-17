<?php

namespace Tests\Feature\DocsPortal;

use Tests\TestCase;

/**
 * The frontend documentation portal at /dev/docs/<token>.
 *
 * The frontend developer has no account in this backend, so the portal is addressed by a secret in
 * the path and nothing else: he opens it, and so does the agent he points at it. What it serves is
 * the documentation tree in docs/ai/frontend — the per-feature documents, the dated deltas under
 * them, and the runnable request packages beside them — grouped by the `feature` and `area` keys the
 * documents carry themselves, so the grouping cannot drift away from the files.
 *
 * These assertions are derived from what is on disk rather than from a fixed list of titles, so the
 * same suite holds in every backend the portal ships to.
 */
class DocsPortalTest extends TestCase
{
    private const TOKEN = 'testing-docs-portal-token';

    public function test_the_index_shows_every_section_that_has_features(): void
    {
        $response = $this->get($this->url());
        $response->assertOk();

        foreach ($this->areas() as $area) {
            $response->assertSee($area['title'], escape: false);
        }
    }

    public function test_every_delta_on_disk_is_reachable_from_the_portal(): void
    {
        $handoffs = glob(base_path('docs/ai/frontend/handoff/*.md')) ?: [];
        $this->assertNotEmpty($handoffs, 'The documentation tree has no deltas at all.');

        $listed = collect($this->areas())->pluck('features')->flatten(1)
            ->pluck('handoffs')->flatten(1)->pluck('path')->all();

        foreach ($handoffs as $path) {
            $this->assertContains('docs/ai/frontend/handoff/'.basename($path), $listed,
                basename($path).' is not reachable: its front-matter names no feature the portal knows.');
        }
    }

    public function test_every_feature_a_delta_names_is_a_feature_the_portal_knows(): void
    {
        // A delta lists the features it touched; the first is where it is filed and the rest are
        // cross-references. A slug that matches no feature is dropped without a sound — the
        // cross-reference simply never appears — so a typo in front-matter has to fail here.
        $known = collect($this->areas())->pluck('features')->flatten(1)->pluck('slug')->all();

        foreach (glob(base_path('docs/ai/frontend/handoff/*.md')) ?: [] as $path) {
            $matched = preg_match('/^feature:\s*(.+)$/m', (string) file_get_contents($path), $m);
            $this->assertSame(1, $matched, basename($path).' carries no feature in its front-matter.');

            preg_match_all('/"([\w-]+)"/', $m[1], $slugs);

            foreach ($slugs[1] as $slug) {
                $this->assertContains($slug, $known,
                    basename($path)." names the feature '{$slug}', which the portal does not know.");
            }
        }
    }

    public function test_a_feature_page_lists_its_deltas_newest_first(): void
    {
        $feature = collect($this->areas())->pluck('features')->flatten(1)
            ->sortByDesc(fn ($f) => count($f['handoffs']))->first();

        $this->assertGreaterThan(1, count($feature['handoffs']),
            'No feature has more than one delta, so ordering cannot be asserted.');

        $response = $this->get($this->url('/f/'.$feature['slug']));
        $response->assertOk();
        $response->assertSeeInOrder(array_column($feature['handoffs'], 'title'), escape: false);

        $dates = array_column($feature['handoffs'], 'date');
        $sorted = $dates;
        rsort($sorted);
        $this->assertSame($sorted, $dates, 'The portal listed the deltas out of date order.');
    }

    public function test_a_delta_renders_and_can_be_downloaded(): void
    {
        $delta = collect($this->areas())->pluck('features')->flatten(1)
            ->pluck('handoffs')->flatten(1)->first();

        $slug = basename($delta['path'], '.md');
        $this->get($this->url('/d/'.$slug))->assertOk()->assertSee($delta['title'], escape: false);

        $raw = $this->get($this->url('/raw/'.$delta['path'].'?download=1'));
        $raw->assertOk();
        $raw->assertHeader('Content-Type', 'text/markdown; charset=UTF-8');
        $this->assertStringContainsString('attachment; filename="'.basename($delta['path']).'"',
            (string) $raw->headers->get('Content-Disposition'));
    }

    public function test_an_unknown_feature_and_an_unknown_delta_are_not_found(): void
    {
        $this->get($this->url('/f/no-such-feature'))->assertNotFound();
        $this->get($this->url('/d/2030-01-01-no-such-delta'))->assertNotFound();
    }

    public function test_only_indexed_files_are_served(): void
    {
        // The route parameter accepts slashes so a documentation path can be addressed as itself;
        // the whitelist is what keeps it inside the documentation tree.
        $this->get($this->url('/raw/.env'))->assertNotFound();
        $this->get($this->url('/raw/composer.json'))->assertNotFound();
        $this->get($this->url('/raw/../../.env'))->assertNotFound();
    }

    public function test_the_index_json_carries_direct_urls_for_an_agent(): void
    {
        $response = $this->get($this->url('/index.json'));
        $response->assertOk();
        $response->assertHeader('X-Robots-Tag', 'noindex, nofollow');

        $delta = collect($response->json('areas'))->pluck('features')->flatten(1)
            ->pluck('handoffs')->flatten(1)->first();

        $this->assertNotNull($delta);
        $this->assertStringContainsString('/raw/'.$delta['path'], $delta['url']);
        $this->assertArrayHasKey('breaking', $delta);
        $this->assertArrayHasKey('lang', $delta);
    }

    public function test_every_section_a_document_names_has_a_title_in_the_config(): void
    {
        // A document's `area` that the config does not know still renders — under its own slug,
        // in Latin, next to sections that have proper names. Nothing else catches that, because
        // the page and the index both read the same config: the mismatch is only visible against
        // the files themselves.
        $configured = array_keys((array) config('docs_portal.areas'));
        $paths = array_merge(
            glob(base_path('docs/ai/frontend/*.md')) ?: [],
            glob(base_path('docs/ai/frontend/handoff/*.md')) ?: [],
        );

        foreach ($paths as $path) {
            if (preg_match('/^area:\s*([\w-]+)$/m', (string) file_get_contents($path), $m)) {
                $this->assertContains($m[1], $configured,
                    basename($path)." is filed under the section '{$m[1]}', which config/docs_portal.php does not name.");
            }
        }
    }

    /** @return list<array<string, mixed>> */
    private function areas(): array
    {
        return $this->get($this->url('/index.json'))->json('areas');
    }

    private function url(string $path = ''): string
    {
        return '/dev/docs/'.self::TOKEN.$path;
    }
}
