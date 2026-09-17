<?php

namespace App\Support\DocsPortal;

/**
 * Reads the frontend documentation tree and groups it the way the frontend developer
 * thinks about it: sections, features inside them, and the dated deltas under each
 * feature. The grouping is not maintained anywhere separately — it is the `feature`
 * and `area` keys the documents carry in their own front-matter, so a document that
 * moves between features moves by being edited, and cannot fall out of an index.
 */
final class DocsIndex
{
    /** @var array<string, array<string, mixed>>|null */
    private ?array $documents = null;

    /** The base path is injectable so a test can point the index at a fixture tree. */
    public function __construct(private readonly ?string $base = null) {}

    private function base(): string
    {
        return $this->base ?? base_path();
    }

    /**
     * Both conditions are deliberate. Without a token in .env the portal does not exist
     * even locally; with a token but the wrong environment it does not exist either.
     */
    public static function isEnabled(): bool
    {
        $token = (string) config('docs_portal.token');

        return $token !== ''
            && in_array((string) app()->environment(), (array) config('docs_portal.environments'), true);
    }

    public function frontendPath(): string
    {
        return $this->base().'/'.trim((string) config('docs_portal.root'), '/').'/frontend';
    }

    /** The project-wide handoff that the portal opens on. */
    public function master(): ?array
    {
        $path = $this->base().'/'.trim((string) config('docs_portal.root'), '/').'/README.md';

        if (! is_file($path)) {
            return null;
        }

        [$meta, $body] = FrontMatter::parse((string) file_get_contents($path));

        return [
            'title' => $meta['title'] ?? 'Документація для фронтенду',
            'lang' => $meta['lang'] ?? 'uk',
            'updated' => $meta['updated'] ?? null,
            'path' => $this->relative($path),
            'body' => $body,
        ];
    }

    /** @return array<string, array<string, mixed>> feature slug => feature */
    public function features(): array
    {
        $primary = [];      // slug => the feature's own document
        $extra = [];        // slug => further reference documents filed under it
        $handoffs = [];     // slug => the deltas whose first feature is this one
        $mentions = [];     // slug => deltas that changed this feature while filed under another
        $areas = [];        // slug => section
        $named = [];        // slug => name carried by a delta, for features with no document

        foreach ($this->documents() as $doc) {
            $slug = $doc['feature'][0] ?? null;

            if (! is_string($slug)) {
                continue;
            }

            $areas[$slug] = $doc['area'] ?? $areas[$slug] ?? 'platform';

            if ($doc['type'] === 'feature') {
                $primary[$slug] = $doc;
            } elseif ($doc['type'] === 'reference') {
                $extra[$slug][] = $doc;
            } else {
                $handoffs[$slug][] = $doc;

                // A feature with no document of its own takes its name from the deltas, so the
                // gap shows up as a missing document rather than as a section named after a slug.
                if (is_string($doc['feature_title'])) {
                    $named[$slug] = $doc['feature_title'];
                }

                // A delta that touches several features is listed under each of the others too, so
                // the developer working on the cart finds the delta that was filed under the
                // catalogue and changed the cart as well.
                foreach (array_slice($doc['feature'], 1) as $also) {
                    $mentions[$also][] = $doc;
                }
            }
        }

        $byDateDescending = static fn (array $a, array $b): int => strcmp((string) $b['date'], (string) $a['date']);
        $features = [];

        foreach ($areas as $slug => $area) {
            $deltas = $handoffs[$slug] ?? [];
            $touching = $mentions[$slug] ?? [];
            usort($deltas, $byDateDescending);
            usort($touching, $byDateDescending);
            $dates = array_filter(array_column($deltas, 'date'));

            $features[$slug] = [
                'slug' => $slug,
                'title' => $primary[$slug]['title'] ?? $named[$slug] ?? $slug,
                'area' => $primary[$slug]['area'] ?? $area,
                'doc' => $primary[$slug] ?? null,
                'extra' => $extra[$slug] ?? [],
                'handoffs' => $deltas,
                'mentions' => $touching,
                'updated' => $dates ? max($dates) : ($primary[$slug]['updated'] ?? null),
                'breaking' => count(array_filter($deltas, static fn (array $doc): bool => (bool) $doc['breaking'])),
                'stale' => count(array_filter($deltas, static fn (array $doc): bool => $doc['status'] === 'superseded')),
            ];
        }

        return $features;
    }

    /** @return list<array<string, mixed>> sections in display order, each with its features */
    public function areas(): array
    {
        $titles = (array) config('docs_portal.areas');
        $features = $this->features();
        $areas = [];

        foreach (array_keys($titles) as $slug) {
            $areas[$slug] = ['slug' => $slug, 'title' => $titles[$slug], 'features' => []];
        }

        foreach ($features as $feature) {
            $slug = $feature['area'];
            $areas[$slug] ??= ['slug' => $slug, 'title' => $slug, 'features' => []];
            $areas[$slug]['features'][] = $feature;
        }

        foreach ($areas as &$area) {
            usort($area['features'], static fn ($a, $b) => strcmp((string) $b['updated'], (string) $a['updated']));
        }

        unset($area);

        return array_values(array_filter($areas, static fn ($area) => $area['features'] !== []));
    }

    public function feature(string $slug): ?array
    {
        return $this->features()[$slug] ?? null;
    }

    public function handoff(string $slug): ?array
    {
        $doc = $this->documents()['handoff/'.$slug] ?? null;

        return $doc && $doc['type'] === 'handoff' ? $doc : null;
    }

    /** Everything the portal is allowed to serve as a file, as relative project paths. */
    public function servable(): array
    {
        $files = [];

        foreach (['/*.md', '/handoff/*.md', '/http/*.http', '/openapi/*.json', '/openapi/*.yaml', '/openapi/*.yml'] as $pattern) {
            foreach (glob($this->frontendPath().$pattern) ?: [] as $path) {
                $files[$this->relative($path)] = true;
            }
        }

        return $files;
    }

    /** @return array<string, mixed> the machine-readable index the frontend's agent reads */
    public function toArray(callable $url): array
    {
        $areas = [];

        foreach ($this->areas() as $area) {
            $features = [];

            foreach ($area['features'] as $feature) {
                $features[] = [
                    'slug' => $feature['slug'],
                    'title' => $feature['title'],
                    'updated' => $feature['updated'],
                    'document' => $feature['doc'] ? $this->export($feature['doc'], $url) : null,
                    'handoffs' => array_map(fn ($doc) => $this->export($doc, $url), $feature['handoffs']),
                ];
            }

            $areas[] = ['slug' => $area['slug'], 'title' => $area['title'], 'features' => $features];
        }

        return [
            'generated_at' => now()->toIso8601String(),
            'master' => ($master = $this->master()) ? ['title' => $master['title'], 'url' => $url($master['path'])] : null,
            'areas' => $areas,
        ];
    }

    private function export(array $doc, callable $url): array
    {
        return [
            'title' => $doc['title'],
            'date' => $doc['date'] ?? $doc['updated'] ?? null,
            'status' => $doc['status'],
            'breaking' => $doc['breaking'],
            'lang' => $doc['lang'],
            'path' => $doc['path'],
            'url' => $url($doc['path']),
            'http' => array_map($url, $doc['http']),
            'openapi' => array_map($url, $doc['openapi']),
        ];
    }

    /** @return array<string, array<string, mixed>> */
    private function documents(): array
    {
        if ($this->documents !== null) {
            return $this->documents;
        }

        $documents = [];

        foreach (glob($this->frontendPath().'/*.md') ?: [] as $path) {
            $documents[basename($path, '.md')] = $this->read($path, 'feature');
        }

        foreach (glob($this->frontendPath().'/handoff/*.md') ?: [] as $path) {
            $documents['handoff/'.basename($path, '.md')] = $this->read($path, 'handoff');
        }

        return $this->documents = $documents;
    }

    private function read(string $path, string $fallbackType): array
    {
        [$meta, $body] = FrontMatter::parse((string) file_get_contents($path));

        $feature = $meta['feature'] ?? [];
        $feature = is_array($feature) ? $feature : [$feature];

        return [
            'slug' => basename($path, '.md'),
            'path' => $this->relative($path),
            'title' => (string) ($meta['title'] ?? basename($path, '.md')),
            'feature' => array_values(array_filter($feature, 'is_string')),
            'feature_title' => $meta['feature_title'] ?? null,
            'area' => $meta['area'] ?? null,
            'type' => (string) ($meta['type'] ?? $fallbackType),
            'date' => $meta['date'] ?? null,
            'updated' => $meta['updated'] ?? $meta['date'] ?? null,
            'status' => (string) ($meta['status'] ?? 'current'),
            'superseded_by' => $meta['superseded_by'] ?? null,
            'breaking' => (bool) ($meta['breaking'] ?? false),
            'lang' => (string) ($meta['lang'] ?? 'uk'),
            'http' => (array) ($meta['http'] ?? []),
            'openapi' => (array) ($meta['openapi'] ?? []),
            'body' => $body,
        ];
    }

    private function relative(string $path): string
    {
        return ltrim(str_replace($this->base(), '', $path), '/');
    }
}
