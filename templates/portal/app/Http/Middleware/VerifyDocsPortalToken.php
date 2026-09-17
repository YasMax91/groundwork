<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * The portal is addressed by a secret in the path, so that the frontend developer and
 * the agent he points at it both reach it with a plain GET and no session. A wrong or
 * missing secret answers 404, not 403: a guesser learns nothing about whether the page
 * exists at all.
 */
final class VerifyDocsPortalToken
{
    public function handle(Request $request, Closure $next): Response
    {
        $expected = (string) config('docs_portal.token');
        $given = (string) $request->route('token');

        abort_unless($expected !== '' && hash_equals($expected, $given), 404);

        return $next($request);
    }
}
