---
description: Add a source to the wiki: save it, then create and update cited pages
argument-hint: "<file path, URL or pasted text>"
---

Ingest this source into the wiki, following the `grove` skill ("Ingesting a source"): {{ARGS}}

1. Resume first (`guide`, `editor_conformance`).
2. Read the source in full. If it is a file path, read the file; if it is a URL, fetch it; otherwise it is the
   text itself. If it is long, work through it in parts.
3. Look for existing pages on its subjects (`search`, `people`, `metadata`) before planning.
4. Build one batch: `add_raw` with the source (make it citable with `^id` markers or cite its headings),
   vocabulary declarations, then the page operations. Run `editor_check`, fix what it reports, then
   `editor_apply`.
5. Tell the user what was created and updated, anything that contradicts an existing page, and anything you
   were unsure of. Offer to ingest the next source.
