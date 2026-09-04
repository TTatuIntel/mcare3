<?php

namespace App\Support;

/**
 * The content model behind every email mCare sends.
 *
 * Each mailable describes *what* it needs to say as an ordered list of typed
 * blocks — a paragraph, a one-time code, a call to action, a table of facts —
 * and never how any of it looks. `resources/views/mail/layout.blade.php`
 * renders those blocks as branded HTML and `layout-text.blade.php` renders the
 * same blocks as plain text, so both parts of every multipart message always
 * carry identical information.
 *
 * Adding a new email means composing blocks, not writing another template.
 * Restyling the whole application's mail means editing one layout.
 */
final class MailContent
{
    public const TONE_INFO = 'info';

    public const TONE_SUCCESS = 'success';

    public const TONE_WARNING = 'warning';

    public const TONE_DANGER = 'danger';

    /** @var list<array<string, mixed>> */
    private array $blocks = [];

    private string $eyebrow = '';

    private string $heading = '';

    private string $preheader = '';

    private ?string $greeting = null;

    private ?string $footerNote = null;

    /** @var list<array{label: string, url: string}> */
    private array $footerLinks = [];

    public static function make(): self
    {
        return new self;
    }

    /**
     * Small capitalised label above the heading — the category of the message
     * ("Account security", "Care record"). Gives the reader the gist before
     * they read a word of body copy.
     */
    public function eyebrow(string $text): self
    {
        $this->eyebrow = $text;

        return $this;
    }

    /** The large in-body headline. Usually mirrors the subject line. */
    public function heading(string $text): self
    {
        $this->heading = $text;

        return $this;
    }

    /**
     * The grey line inbox lists show beside the subject. Left unset, clients
     * scrape the first words of the body, which is rarely the useful summary.
     */
    public function preheader(string $text): self
    {
        $this->preheader = $text;

        return $this;
    }

    /** "Hello Amara," — pass null for transactional mail with no addressee. */
    public function greeting(?string $name): self
    {
        $name = trim((string) $name);
        $this->greeting = $name === '' ? 'Hello,' : "Hello {$name},";

        return $this;
    }

    public function paragraph(string $text): self
    {
        return $this->push(['type' => 'paragraph', 'text' => $text]);
    }

    /** A section title inside the body, for mail that covers several topics. */
    public function subheading(string $text): self
    {
        return $this->push(['type' => 'subheading', 'text' => $text]);
    }

    /**
     * A one-time code, shown large and letter-spaced so it can be read off a
     * phone screen without mistaking 0 for O.
     */
    public function code(string $value, ?string $caption = null): self
    {
        return $this->push([
            'type' => 'code',
            'value' => trim($value),
            'caption' => $caption,
        ]);
    }

    /**
     * The primary action. Always paired with the raw URL underneath, because
     * a button is unclickable in a text part and in locked-down clients.
     */
    public function button(string $label, string $url, string $tone = self::TONE_INFO): self
    {
        return $this->push([
            'type' => 'button',
            'label' => $label,
            'url' => $url,
            'tone' => $tone,
        ]);
    }

    /**
     * Label/value rows — credentials, appointment details, alert readings.
     *
     * @param  array<string, string|int|float|null>  $rows
     */
    public function facts(array $rows, ?string $title = null): self
    {
        $clean = [];
        foreach ($rows as $label => $value) {
            $value = is_string($value) ? trim($value) : $value;
            if ($value === null || $value === '') {
                continue;
            }
            $clean[(string) $label] = (string) $value;
        }

        return $clean === [] ? $this : $this->push([
            'type' => 'facts',
            'title' => $title,
            'rows' => $clean,
        ]);
    }

    /**
     * @param  list<string>  $items
     */
    public function bullets(array $items, ?string $title = null): self
    {
        $items = array_values(array_filter(array_map(
            static fn ($item) => trim((string) $item),
            $items,
        ), static fn (string $item) => $item !== ''));

        return $items === [] ? $this : $this->push([
            'type' => 'bullets',
            'title' => $title,
            'items' => $items,
        ]);
    }

    /**
     * Text the reader must not skim past: a security warning, an expiry, a
     * reason a decision went the way it did.
     */
    public function callout(string $text, string $tone = self::TONE_INFO, ?string $title = null): self
    {
        return $this->push([
            'type' => 'callout',
            'text' => $text,
            'tone' => $tone,
            'title' => $title,
        ]);
    }

    /** Verbatim text — a rejection reason, a clinician's note. Never parsed. */
    public function quote(string $text): self
    {
        return $this->push(['type' => 'quote', 'text' => $text]);
    }

    public function divider(): self
    {
        return $this->push(['type' => 'divider']);
    }

    /** Fine print under the divider: "You received this because…". */
    public function footerNote(string $text): self
    {
        $this->footerNote = $text;

        return $this;
    }

    public function footerLink(string $label, string $url): self
    {
        $this->footerLinks[] = ['label' => $label, 'url' => $url];

        return $this;
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(): array
    {
        return [
            'eyebrow' => $this->eyebrow,
            'heading' => $this->heading,
            'preheader' => $this->preheader !== '' ? $this->preheader : $this->heading,
            'greeting' => $this->greeting,
            'blocks' => $this->blocks,
            'footerNote' => $this->footerNote,
            'footerLinks' => $this->footerLinks,
        ];
    }

    /**
     * @param  array<string, mixed>  $block
     */
    private function push(array $block): self
    {
        $this->blocks[] = $block;

        return $this;
    }
}
