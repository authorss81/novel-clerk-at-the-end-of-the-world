# Revised Novel Fleet Repository Plan

## Scope

This remains a local planning package. Nothing is pushed and `llops-android` is not touched.

After approval, create separate public repositories for the 20 novels. Each repository receives its own API key, state, workflow, and independent progress.

## Repository Naming

Use the final catalog titles after the overlap-revision review. Each repository is independent:

```text
authorss81/novel-<slug>
```

## Primary and Fallback Models

The primary model requested is:

```text
opencode/space-bunny-free
```

The local command:

```text
opencode models
```

confirmed these free-tag models:

```text
opencode/space-bunny-free
opencode/muse-spark-1.3-contributor-free
opencode/muse-spark-1.2-contributor-free
opencode/nemotron-3-ultra-free
opencode/nemotron-3.5-lightning-free
opencode/mimo-v2.6-flash-free
opencode/ling-3.0-flash-fin-free
```

The production workflow will run the command again before generation. If the primary disappears, the workflow records the failure and uses an approved fallback only for a classified provider error, rate limit, timeout, or unavailable model.

Each repository has its own `OPENCODE_API_KEY` secret. The controller must never store or print those keys.

## Outline System

Each repository receives a complete outline before chapter batches are generated:

- `outline/series.md`: full series arc and ending.
- `outline/ending.md`: final destination, final conflict, and resolution.
- `outline/volume-01.md`: first volume arc.
- `outline/batches/volume-01-batch-0001.md`: chapter cards for Chapters 1–10.
- Later batch files: chapter cards for each 10–20 chapter batch.
- `bible/`: world, characters, power rules, terminology, and themes.
- `state/`: summaries, continuity, open threads, and phase ledger.

A novel is not allowed to drift into an improvised series. The ending and volume destinations are planned first, while the details between them remain flexible.

## Phase System

One phase handles a batch of 10–20 chapters, not one chapter.

```text
bootstrap
series outline
volume outline
batch plan
batch 0001: chapters 1–10
batch 0002: chapters 11–20
batch 0003: chapters 21–30
volume audit
volume 02 outline
batch 0004
```

The default pilot batch is 10 chapters. A 20-chapter batch is permitted after output limits and quality are measured.

Each batch prompt reads the series outline, volume outline, batch cards, rolling summaries, continuity state, and the last two or three chapters for immediate voice. It does not load the whole manuscript.

After a batch:

- Validate all expected chapters.
- Review the batch as a whole.
- Check the planned midpoint and climax.
- Update summaries and continuity.
- Commit the batch.
- Dispatch the next batch.

A volume audit runs after all volume batches finish. The next volume is not generated until the audit passes.

## Repository Isolation

Every repository uses a unique concurrency group:

```text
novel-<repository>-writer
```

Different repositories can run simultaneously. Two batches from the same repository cannot run simultaneously.

The phase ledger is authoritative. It stores phase ID, status, attempts, base commit, result commit, actual model, fallback status, lease expiry, and next retry time. Marker files alone are not sufficient. The controller is the only authority allowed to change phase status; a writer may update story state but must leave the phase ledger untouched.

## Public Draft Issue

A public repository makes every committed draft visible. If unpublished drafts are required, use private repositories instead. Public and private visibility cannot be mixed as if a public branch were private.

## Pilot

Do not immediately activate all 20 repositories.

1. Create five repositories after approval.
2. Add one unique API key to each.
3. Run the model probe.
4. Generate the first 10-chapter batch in each.
5. Review prose, continuity, batch size, cost, and runtime.
6. Expand to the remaining 15 repositories only after the pilot passes.

## Approval Still Required

- Revised 20-novel catalog.
- Ten-chapter default batch size.
- Twenty-chapter maximum batch size.
- Primary and fallback model chain.
- Public versus private repository policy.
- Direct writing branch versus pull-request policy.
- First five-repository pilot.
