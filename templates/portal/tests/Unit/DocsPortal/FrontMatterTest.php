<?php

namespace Tests\Unit\DocsPortal;

use App\Support\DocsPortal\FrontMatter;
use PHPUnit\Framework\TestCase;

/**
 * The front-matter parser reads the block that carries a document's grouping, name and date.
 *
 * It is a fixed subset rather than YAML, because the portal ships to backends that do not all have
 * symfony/yaml installed. The subset has to survive the shapes our documents actually use: titles
 * that contain a colon, lists of paths, booleans, and a body that itself contains a `---` rule.
 */
class FrontMatterTest extends TestCase
{
    public function test_it_reads_the_keys_a_document_carries(): void
    {
        [$meta, $body] = FrontMatter::parse(<<<'MD'
            ---
            title: "Каталог: фільтри, сортування, пошук"
            feature: ["catalog", "variants"]
            date: 2026-09-17
            breaking: true
            status: current
            http: []
            ---

            # Заголовок

            Текст.
            MD);

        $this->assertSame('Каталог: фільтри, сортування, пошук', $meta['title']);
        $this->assertSame(['catalog', 'variants'], $meta['feature']);
        $this->assertSame('2026-09-17', $meta['date']);
        $this->assertTrue($meta['breaking']);
        $this->assertSame('current', $meta['status']);
        $this->assertSame([], $meta['http']);
        $this->assertStringStartsWith('# Заголовок', $body);
    }

    public function test_a_horizontal_rule_in_the_body_does_not_end_the_block(): void
    {
        [$meta, $body] = FrontMatter::parse("---\ntitle: \"A\"\n---\n\nfirst\n\n---\n\nsecond\n");

        $this->assertSame('A', $meta['title']);
        $this->assertStringContainsString('second', $body);
    }

    public function test_a_document_without_a_block_is_returned_whole(): void
    {
        [$meta, $body] = FrontMatter::parse("# Заголовок\n\nТекст.\n");

        $this->assertSame([], $meta);
        $this->assertStringStartsWith('# Заголовок', $body);
    }

    public function test_a_quoted_value_may_contain_a_comma_inside_a_list(): void
    {
        [$meta] = FrontMatter::parse("---\nnames: [\"one, two\", \"three\"]\n---\n\nbody\n");

        $this->assertSame(['one, two', 'three'], $meta['names']);
    }
}
