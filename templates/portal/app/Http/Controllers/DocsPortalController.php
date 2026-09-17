<?php

namespace App\Http\Controllers;

use App\Support\DocsPortal\DocsIndex;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\View\View;
use Symfony\Component\HttpFoundation\Response;

final class DocsPortalController extends Controller
{
    public function __construct(private readonly DocsIndex $index) {}

    public function index(string $token): View
    {
        return view('docs-portal.index', [
            'token' => $token,
            'master' => $this->rendered($this->index->master()),
            'areas' => $this->index->areas(),
        ]);
    }

    public function feature(string $token, string $feature): View
    {
        $found = $this->index->feature($feature);

        abort_if($found === null, 404);

        $found['doc'] = $this->rendered($found['doc']);
        $found['extra'] = array_map(fn ($doc) => $this->rendered($doc), $found['extra']);

        return view('docs-portal.feature', ['token' => $token, 'feature' => $found]);
    }

    public function document(string $token, string $slug): View
    {
        $document = $this->index->handoff($slug);

        abort_if($document === null, 404);

        return view('docs-portal.document', [
            'token' => $token,
            'document' => $this->rendered($document),
            'feature' => $this->index->feature($document['feature'][0] ?? ''),
        ]);
    }

    /**
     * Serves a documentation file as itself — the frontend saves it, or points his own
     * agent at the URL. Only paths the index actually found are served, so the `.*`
     * route parameter cannot be walked out of the documentation tree.
     */
    public function raw(Request $request, string $token, string $path): Response
    {
        abort_unless(isset($this->index->servable()[$path]), 404);

        $types = [
            'md' => 'text/markdown; charset=UTF-8',
            'http' => 'text/plain; charset=UTF-8',
            'json' => 'application/json; charset=UTF-8',
            'yaml' => 'application/yaml; charset=UTF-8',
            'yml' => 'application/yaml; charset=UTF-8',
        ];

        $extension = strtolower(pathinfo($path, PATHINFO_EXTENSION));

        return response()->file(base_path($path), array_filter([
            'Content-Type' => $types[$extension] ?? 'text/plain; charset=UTF-8',
            'Content-Disposition' => $request->boolean('download')
                ? 'attachment; filename="'.basename($path).'"'
                : null,
            'X-Robots-Tag' => 'noindex, nofollow',
        ]));
    }

    public function json(string $token): Response
    {
        return response()
            ->json($this->index->toArray(fn (string $path) => route('docs-portal.raw', [
                'token' => $token,
                'path' => $path,
            ])), options: JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT)
            ->header('X-Robots-Tag', 'noindex, nofollow');
    }

    /** @param  array<string, mixed>|null  $document */
    private function rendered(?array $document): ?array
    {
        if ($document === null) {
            return null;
        }

        $document['html'] = Str::markdown($document['body'], [
            'html_input' => 'escape',
            'allow_unsafe_links' => false,
        ]);

        return $document;
    }
}
