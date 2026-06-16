---
name: rag-doc-optimization
description: "How to write Markdown that retrieves and reads well in a RAG store consumed by humans and programming agents — frontmatter metadata schema, self-contained chunk rules, stable anchors and IDs, consistent cross-link format, and glossary linking. Apply when writing or reviewing any document destined for RAG ingestion, to maximize retrieval precision and standalone readability of each chunk."
---

A RAG store retrieves *fragments*, not whole files. A reader (human or agent) often sees one
section with no surrounding context. Optimize for the chunk, not the page. The rules below
make each section retrievable and self-contained.

## 1. Frontmatter is retrieval metadata, not decoration

Every file starts with YAML frontmatter the retriever can filter on. Per-service docs use the
schema in `service-doc-template`; aggregate docs use `system-catalog-template`. Always include:
- a stable **id** (`service_id` / `doc_id`) that equals the filename stem,
- **type** and **domain**/**tags** for filtering,
- **source_commit** + **last_updated** for staleness.

Keep tag vocabulary consistent across docs (same spelling, same casing) — inconsistent tags
fragment retrieval. Prefer a small controlled set: the domain, the integration tech, the
capability. Treat the vocabulary as **controlled**: reuse an existing tag/term before coining a
new one (`http-api` not `rest`/`web-api`; `solace` not `messaging`/`pubsub`; one spelling per
domain). The glossary (`_glossary.md`) is the controlled vocabulary for domain *terms*; the tag
set is its counterpart for retrieval *facets*. A reviewer flags a tag that's a near-duplicate of
an existing one.

Aggregate docs use a stable `type` facet so retrieval can include or exclude them as a class —
the controlled set is: `catalog`, `registry`, `matrix`, `context`, `process-flows`,
`cross-cutting`, `decisions`, `glossary`, `dataflow`. Per-service docs use `type` =
`http-api | worker | library | hybrid`.

## 2. Each section stands alone

Assume the chunk is retrieved with nothing above it.
- **Lead with the subject, not a pronoun.** "Payments API publishes..." not "It publishes...".
- **No "see above" / "as mentioned" / "the previous section."** If a fact is needed to
  understand the chunk, restate it in one clause.
- **Repeat the service name** in the first sentence of major sections. Mild redundancy across
  chunks is good for retrieval; it's not prose to be de-duplicated.
- **Keep one concept per H2.** If a section answers two unrelated questions, split it so each
  retrieves cleanly.

## 3. Headings are chunk boundaries

- Use a single H1 (the service/document title) and H2 for every top-level section the template
  defines. Most retrievers chunk on headings — predictable H2s give predictable chunks.
- Don't nest deeper than H3. Deep nesting produces tiny, context-poor chunks.
- Keep heading text descriptive and stable: "Data flow", "Public interface" — an agent and a
  retriever both key off these exact names.

## 4. Stable IDs, filenames, and anchors

- Filename = the id (`payments-api.md`). Deterministic, kebab-case, never spaces.
- Cross-link by filename/id, not by display name: `[Orders API](orders-api.md)`.
- When linking to a section, use the GitHub-style anchor (`payments-api.md#data-flow`).
- Aggregate docs use the `_` prefix (`_service-catalog.md`) so they're easy to include/exclude
  in retrieval filters.

## 5. Consistent cross-link format

Always: `[Display Name](service_id.md)`. Maintain a small footer "Cross-references" line so the
graph is navigable from any chunk:
```
## Cross-references
- [Orders API](orders-api.md) · [Service catalog](_service-catalog.md) · [Glossary](_glossary.md)
- Processes: [Order-to-Cash](_process-flows.md#order-to-cash) · Conventions: [Cross-cutting](_cross-cutting.md) · Decisions: [_decisions.md](_decisions.md)
```
A link to a `service_id` that has no doc, or to an aggregate (`_process-flows.md`,
`_cross-cutting.md`, `_decisions.md`, `_system-context.md`) that wasn't produced, is a dangling
link — a reviewer flags it.

## 6. Machine-readable beats prose for structured facts

Agents parse tables and code blocks far more reliably than paragraphs. For interfaces,
config, flows, dependencies — use the tables defined in the templates. Reserve prose for
*why* (business context, boundaries, rationale) where structure can't carry the meaning.

## 7. Examples must be copy-paste real

Request/response examples, message payloads, and config snippets should be valid and concrete
(real field names from the code), not pseudo-code. An agent may use them verbatim. Redact
secret *values* but keep key *names*.

## 8. Glossary linking

First use of a domain term in a doc links to `_glossary.md`. Define each term once, in the
glossary, owned by one service. Don't redefine inline — link.

## Pre-ingestion checklist (run before declaring a doc done)
- [ ] Valid YAML frontmatter with id == filename, type, domain/tags, source_commit, last_updated.
- [ ] Every H2 from the template present (or explicitly marked N/A in one line).
- [ ] No "see above"/pronoun-led sections; service name appears early in each major section.
- [ ] All cross-links resolve to existing ids; glossary terms link to `_glossary.md`.
- [ ] Structured facts (interface, config, flow) are in tables, not buried in prose.
- [ ] Examples are concrete and secret-free.
- [ ] Headings ≤ H3; one concept per H2.
