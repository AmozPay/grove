---
description: Answer a question from the wiki, with citations
argument-hint: "<question>"
---

Answer this question from the wiki, following the `llm-wiki` skill ("Answering a question"): {{ARGS}}

Use `search` (twice with different words if the first finds little), `cite` the sources of the claims that
matter, and answer with the page and source of each claim. Say what the wiki does not cover. Do not use
knowledge from outside the wiki unless you label it as such. If the answer is worth keeping, offer to file
it as a `query` page.
