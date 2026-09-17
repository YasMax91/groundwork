---
description: Install the frontend documentation portal into a Laravel project — a token-gated page on development and staging that serves docs/ai/frontend to the frontend developer and his agent. Use when onboarding a project that has no portal yet, or when the documentation already exists but has no front-matter to group it by.
---

# Install the frontend documentation portal

The frontend developer has no account in this backend. Without a portal the handoff docs reach him
by someone remembering to send files, which means the version he reads is whichever one was attached
last. The portal removes that step: one secret URL, always current, grouped the way the system is
actually shaped.

## What gets installed

Thirteen files from `${CLAUDE_SKILL_DIR}/../../templates/portal/`, at the same paths:

```
config/docs_portal.php                       the gate and the section titles
app/Support/DocsPortal/FrontMatter.php       front-matter parser (no YAML dependency)
app/Support/DocsPortal/DocsIndex.php         scans the tree, builds sections → features → deltas
app/Http/Controllers/DocsPortalController.php
app/Http/Middleware/VerifyDocsPortalToken.php
routes/docs-portal.php
resources/views/docs-portal/*.blade.php      four views, no build step, no CDN
tests/Feature/DocsPortal/*.php               two suites: behaviour and the gate
tests/Unit/DocsPortal/FrontMatterTest.php
```

They depend on nothing the project does not already have: `Str::markdown()` ships with the framework,
and the front-matter parser is deliberately not YAML, because `symfony/yaml` is not present in every
backend.

## Steps

1. **Copy the files.** Same relative paths, no edits yet.

2. **Register the routes** — append to `routes/web.php`:

   ```php
   // The frontend documentation portal exists only on development and staging, and only
   // when DEV_DOCS_TOKEN is set. See config/docs_portal.php.
   if (App\Support\DocsPortal\DocsIndex::isEnabled()) {
       require __DIR__.'/docs-portal.php';
   }
   ```

3. **Name this project's sections** in `config/docs_portal.php` `areas`. The shipped pair is a
   placeholder. Sections are the reader's map of the system — use the words the team uses. A
   storefront splits into catalogue / purchase / buyer / content / platform; a back-office CRM splits
   by the work it coordinates, not by those.

4. **Pin the token for the test suite** in `phpunit.xml`, inside `<php>`. Projects differ: some pin
   `<env>`, some only `<server>`. Laravel's Env repository reads `$_SERVER`, so the `<server>` entry
   is the one that must be there — add both:

   ```xml
   <env name="DEV_DOCS_TOKEN" value="testing-docs-portal-token" force="true"/>
   <server name="DEV_DOCS_TOKEN" value="testing-docs-portal-token" force="true"/>
   ```

   Without it the routes are not registered during tests and the whole suite passes vacuously.

5. **Add the token to the `.env` templates** — `.env.example` and any `.env.<environment>.example`
   for a **non-production** environment. Never to a production template:

   ```
   # The frontend documentation portal at /dev/docs/<token> (docs/ai). It is registered only
   # when this token is set AND APP_ENV is one of DEV_DOCS_ENVS, which never contains
   # production — on production the routes do not exist and the URL answers a plain 404.
   DEV_DOCS_TOKEN=
   # DEV_DOCS_ENVS=local,development,staging,testing
   ```

6. **Document it in `DEPLOY.md`** if the project has one: the URL shape, the two conditions, and
   `openssl rand -hex 24` to generate a token per environment. Rotating it is an `.env` edit plus
   `config:cache`; the old URL dies immediately.

7. **Write the master handoff** — `docs/ai/README.md`, the page the portal opens on. Ukrainian,
   with front-matter `type: master`. What this backend is, the one domain fact that changes how the
   UI must behave, where the environments are, how the three document types differ, and which
   features have no consolidated document yet. Ground every line in the code and the deploy docs —
   never invent an environment URL.

8. **Run the tests.** `DocsPortalTest`, `DocsPortalGateTest`, `FrontMatterTest`. They assert the
   invariants that nothing else catches — see below.

## When the project already has documentation

Existing docs carry no front-matter, so the portal cannot see them. Stamping it is the real work and
it is a judgement call, not a script:

1. **Derive the feature map from the documents themselves.** Most handoffs name their reference docs
   in the header block — that is evidence, not a guess. Read the H1 of the rest and assign by meaning.
2. **A feature's slug is the basename of its reference doc.** A feature with no reference doc still
   gets a name: put `feature_title:` on its handoffs, so the gap shows as a missing document instead
   of a section named after a slug.
3. **Mark superseded deltas** — `status: superseded` + `superseded_by:` — only where the text says so.
   A later document that redefines the same fields is evidence; a hunch is not. Never rewrite a
   delta's body: it is a dated record.
4. `breaking: true` is about the reader's existing code, not the size of the change. An additive
   field is not breaking; a field that kept its type and changed its meaning is.

The front-matter contract is specified in `${CLAUDE_SKILL_DIR}/../frontend-handoff/SKILL.md`.

## Three invariants the tests hold

Each exists because the failure is otherwise silent:

- **Every delta is reachable.** A handoff whose `feature` names nothing the portal knows simply never
  appears — no error, no empty section.
- **Every cross-reference resolves.** A delta lists the features it touched; a typo in the second or
  third slug drops that cross-reference without a sound.
- **Every section has a title in the config.** A document filed under an unknown `area` renders under
  its own slug, in Latin, beside sections that have proper names. The page and the index read the
  same config, so only a check against the files catches it.

## What the portal deliberately does not do

It serves only what the index found — the `.*` route parameter cannot be walked out of the
documentation tree. It renders markdown with HTML escaped. It answers 404 for a wrong token rather
than 403. And it holds no state of its own: the grouping is the front-matter, read on every request,
so it cannot drift away from the files.
