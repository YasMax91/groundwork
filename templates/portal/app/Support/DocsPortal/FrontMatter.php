<?php

namespace App\Support\DocsPortal;

/**
 * Parser for the front-matter block the frontend documents carry.
 *
 * Deliberately not a YAML implementation: the block is written by us, to a fixed shape
 * — flat `key: value` lines whose values are a quoted string, a bracketed list, a
 * boolean or a bare word. Keeping the parser to that subset means the portal ships to
 * every project without depending on symfony/yaml, which is only present here through
 * l5-swagger and is absent from several of our other backends.
 */
final class FrontMatter
{
    /**
     * @return array{0: array<string, mixed>, 1: string} the metadata and the body without it
     */
    public static function parse(string $contents): array
    {
        $contents = str_replace("\r\n", "\n", $contents);

        if (! str_starts_with($contents, "---\n")) {
            return [[], $contents];
        }

        $end = strpos($contents, "\n---\n", 4);

        if ($end === false) {
            return [[], $contents];
        }

        $meta = [];

        foreach (explode("\n", substr($contents, 4, $end - 4)) as $line) {
            if (trim($line) === '' || str_starts_with(ltrim($line), '#')) {
                continue;
            }

            $colon = strpos($line, ':');

            if ($colon === false) {
                continue;
            }

            $meta[trim(substr($line, 0, $colon))] = self::value(trim(substr($line, $colon + 1)));
        }

        return [$meta, ltrim(substr($contents, $end + 5), "\n")];
    }

    private static function value(string $raw): string|bool|array|null
    {
        if ($raw === '') {
            return null;
        }

        if (str_starts_with($raw, '[')) {
            $inner = trim(rtrim($raw, ']'), '[');

            if (trim($inner) === '') {
                return [];
            }

            // Split on commas that sit outside quotes, so a quoted value may contain one.
            preg_match_all('/"(?:[^"\\\\]|\\\\.)*"|[^,]+/', $inner, $matches);

            return array_values(array_filter(array_map(
                static fn (string $item): string|bool => self::scalar(trim($item)),
                $matches[0],
            ), static fn ($item) => $item !== ''));
        }

        return self::scalar($raw);
    }

    private static function scalar(string $raw): string|bool
    {
        if ($raw === 'true') {
            return true;
        }

        if ($raw === 'false') {
            return false;
        }

        if (strlen($raw) >= 2 && str_starts_with($raw, '"') && str_ends_with($raw, '"')) {
            return stripcslashes(substr($raw, 1, -1));
        }

        return $raw;
    }
}
