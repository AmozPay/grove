---
description: Create a new, empty LLM wiki
argument-hint: "[domain, in one line]"
---

Create a new wiki with the `llm-wiki` skill's conventions.

1. Ask the user, if they have not said: what the wiki covers (one line), and a few starting tags.
2. Run (a shell command; it knows where the wiki goes, and refuses a wiki that already has files):

   `{{RUN}} wikileaf editor init --domain "<domain>" --tag <tag1>,<tag2>`

   The domain: {{ARGS}}.
3. Call `guide` and show the user the domain and rules in two or three lines.
4. Remind them that the first pages need at least two links to other pages: the first `ingest` creates three
   interlinked pages together.
