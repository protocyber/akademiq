# Manual test documents

Step-by-step manual tests for features, run in the browser through the
manual-test hub (`scripts/test-hub`). Each tester's progress is stored on the
hub server per user, so signing in as the same user on another device carries
on where they stopped.

- Hub: `make hub-up` (repo root), then open the URL it prints
  (`https://akademiq-testing.oracle.fitrah.web.id` on the oracle dev VM).
- Users: `make hub-user-add U=<id> NAME="Name" ROLE=admin|tester`,
  `make hub-passwd U=<id>`, `make hub-users`. See `scripts/test-hub/README.md`.

## File naming

`YYYY-MM-DD-<feature>-manual-test.html`. The file name without `.html` is the
document's URL slug (`/d/<slug>`) and the key its progress is saved under, so
do not rename a document that testers have started. Files starting with `_`
are ignored (drafts).

## Markup

A document is a plain HTML file. The hub reads `<title>`, the description meta,
any `<style>` blocks, and the `<body>`; it adds the status buttons, notes,
progress, sidebar and report itself. Do not add your own checkboxes or
`localStorage` code.

```html
<!doctype html>
<html lang="id">
<head>
  <title>Tes Manual Fitur X</title>
  <meta name="description" content="One line shown on the hub index.">
</head>
<body>
  <aside><p>Free text before the first phase: scope, accounts, warnings.</p></aside>

  <section data-phase="setup" data-title="Persiapan">
    <article data-step="S1" data-title="Short step title" data-who="Admin">
      <p>What to do. <code>inline code</code> becomes a click-to-copy chip.</p>
      <pre><code>multi-line commands get a Copy button</code></pre>
      <div class="expect"><p>What should happen.</p></div>
    </article>
  </section>
</body>
</html>
```

| Markup | Meaning |
|---|---|
| `<section data-phase="id" data-title="…">` | A phase. Listed in the sidebar with its own progress. |
| `<article data-step="id" data-title="…" data-who="…">` | A step the tester marks Pass / Fail / Blocked / Skipped (unmarked = Untested), with a note. `data-who` is an optional actor badge. |
| `<div class="expect">` | Expected result, shown as a green box. |
| `<aside>`, `<aside class="warn">`, `<aside class="danger">` | Info / warning / danger callouts. |
| `<code>` inside a step, or `<span class="chip">` | Click to copy. |
| `<input data-var="key" data-default="…">` | A value the tester records (saved with their progress, per user). |
| `<span data-ref="key"></span>` | Shows a recorded value elsewhere in the document. |
| `<a class="app-link" href="{{app}}/path">` | Link with `{{key}}` filled from a recorded value or its `data-default`; opens in a new tab. |

Step ids must be unique within a document and stable: progress is keyed by
step id, so renaming one drops what testers recorded for it. Adding, removing
or reordering steps is safe; open runners reload the document automatically.
