# Revised Phase and Workflow Design

## Repository Model

Use one public repository per novel. Do not modify the existing `llops-android` repository.

Each repository is independent and receives its own model API key. The repositories may run in parallel because their files, branches, state, and credentials are separate.

## Repository Layout

```text
AGENTS.md
NOVEL_SPEC.md
opencode.json
.github/workflows/novels.yml
scripts/novel_runner.sh
.opencode/agent/novel-writer.md
.opencode/agent/novel-reviewer.md
bible/
  premise.md
  world.md
  characters.md
  power-system.md
  themes.md
  terminology.md
outline/
  series.md
  ending.md
  volume-01.md
  volume-02.md
  volume-03.md
  batches/
    volume-01-batch-0001.md
    volume-01-batch-0002.md
chapters/
  volume-01/
    chapter-0001.md
    chapter-0002.md
state/
  current.md
  continuity.md
  open-threads.md
  chapter-summaries.md
  phase-ledger.json
reviews/
  volume-01/
    batch-0001.md
logs/
prompts/
  batch-writer.md
  reviewer.md
  volume-auditor.md
```

## Outline System

Every novel begins with a full planning stack before prose is generated.

### Series outline

The series outline defines:

- The premise and central promise.
- The protagonist's want, need, flaw, and final change.
- The world, power rules, magic limits, technology, and societies.
- The long mystery and its final answer.
- The main antagonist ladder.
- The planned ending and final volume.
- Major relationship milestones.
- The difference between this novel and every other fleet novel.

### Volume outlines

Each volume contains approximately 40–80 chapters. A volume outline defines:

- Its central pressure.
- Its beginning state.
- Its major factions and locations.
- Its escalation steps.
- Its midpoint reversal.
- Its climax.
- The emotional and strategic resolution.
- The new question that motivates the next volume.
- Any planned power or relationship progression.

### Batch outlines

Each batch contains 10–20 chapters. The default is 10 chapters for a pilot; a batch may increase to 20 after measuring model output and quality.

Every batch outline defines:

- Batch goal.
- Starting condition.
- Chapter-by-chapter cards.
- Mid-batch turn.
- Batch climax.
- Character and power changes.
- New open questions.
- Required continuity updates.
- Expected batch word range only as a flexible guide.

A chapter card contains:

```text
Chapter number
POV and location
Immediate goal
Resistance
Major turn
Emotional or practical consequence
Required continuity facts
Ending hook or completed beat
```

## Batch Phase Model

A phase processes 10–20 chapters in one model run. The model is loaded once per phase instead of once per chapter.

### Bootstrap phases

- `phase-000-bootstrap`: create the novel specification and bible.
- `phase-001-series-outline`: create the complete series arc and ending.
- `phase-002-volume-01-outline`: create the first volume and its batches.
- `phase-003-buffer-plan`: create detailed cards for the first 10–20 chapters.

### Batch phases

Each phase writes a complete batch:

```text
workspace/volume-01/batch-0001
workspace/volume-01/batch-0002
workspace/volume-01/batch-0003
```

The writer reads:

- `NOVEL_SPEC.md`
- the series ending outline
- the current volume outline
- the current batch outline
- the previous batch summary
- the previous two or three chapters for immediate voice and continuity
- `state/current.md`
- `state/continuity.md`
- `state/open-threads.md`
- relevant character and world files

The writer does not need to read every previous chapter. The state and previous batch summaries are the long-term memory. Read the previous 20 chapters for immediate voice and continuity; extend to 30 when the model’s verified context budget safely allows it.

The writer must write 10–20 complete chapters in order, with full scenes and natural prose. It updates the chapter summaries, continuity, and open-thread files as it works.

If the model output limit is reached, the phase must stop at a chapter boundary, commit the completed chapters and state, mark the remaining batch as resumable, and continue in the next run. It must never restart completed chapters.

### Batch audit

After every batch:

- Validate all expected chapter files exist.
- Check approximate length without padding.
- Detect duplicate paragraphs and exact repeated sentences.
- Check that each chapter changed the situation.
- Check the batch's planned midpoint and climax occurred.
- Check that no chapter introduced an unapproved canon change.
- Review prose quality and continuity.
- Apply necessary fixes.
- Update the phase ledger and batch summary.

### Volume audit

At the end of every volume:

- Review the entire volume outline against the produced summaries.
- Check unresolved promises and mysteries.
- Check character relationships and consequences.
- Check power progression and costs.
- Check world-building consistency.
- Check the planned volume climax and resolution.
- Create or activate the next volume outline only after the audit passes.

A volume audit is a separate phase. It must not attempt to rewrite the entire volume.

## Self-Dispatch

After a successful batch phase, the workflow sends at most one new `repository_dispatch` event for the same novel.

The selector chooses one explicit next batch by reading `state/phase-ledger.json`, not by scanning hundreds of marker files.

A phase is identified by:

```text
volume
batch
start chapter
end chapter
status
attempt count
lease expiry
base commit
result commit
actual model
fallback used
next retry time
```

A phase is one of:

```text
planned
running
deferred
done
blocked
```

Only the controller may mark a phase done or blocked. Duplicate events must be harmless. A run must claim a phase before writing files and must verify the phase is still incomplete.

A rate-limited phase writes `deferred` and exits quickly. A scheduled safety-net run retries it later. A real failure retries a limited number of times and then writes `blocked` plus an issue.

## Workflow Jobs

The default workflow uses one main worker job so uncommitted files do not need to move between isolated GitHub runners.

### `select-and-claim`

- Reads the phase ledger.
- Claims the lowest incomplete batch.
- Records the base commit and lease expiry.
- Uses a fixed per-novel concurrency group.

### `write-validate-review-fix`

In the same job:

1. Check out the claimed commit.
2. Run the writer agent.
3. Validate chapter count, prose markers, and state changes.
4. Run the read-only reviewer.
5. Run the fixer agent if findings exist.
6. Revalidate.
7. Commit chapter, outline, state, review, and ledger files together.
8. Push to the novel branch.
9. Emit one next-phase dispatch.

Keeping these steps in one job avoids the separate-runner workspace problem.

### `commit-and-dispatch`

If branch protection is enabled, push a batch branch and open a pull request. Do not dispatch the next batch until the branch is merged or the controller explicitly records the batch as the active source.

For a dedicated public novel repository with a bot owner, direct commits to the chosen writing branch are acceptable after the pilot is approved.

## Concurrency

Each repository uses an immutable group:

```yaml
concurrency:
  group: novel-${{ github.repository }}-writer
  cancel-in-progress: false
```

This prevents two writers from changing the same novel. Different repositories have different concurrency groups and may run simultaneously.

Twenty repositories are supported by the architecture. Because each repository has a separate API key, model quotas are less likely to be shared. Account-wide GitHub limits and provider-wide limits still apply.

Start with a five-repository pilot. Expand to all twenty after checking job duration, model failures, and review quality.

## Model Configuration

The primary model requested is:

```text
opencode/space-bunny-free
```

The following free models were confirmed locally with:

```text
opencode models
```

Confirmed free models relevant to the fallback chain:

```text
opencode/space-bunny-free
opencode/muse-spark-1.3-contributor-free
opencode/muse-spark-1.2-contributor-free
opencode/nemotron-3-ultra-free
opencode/nemotron-3.5-lightning-free
opencode/mimo-v2.6-flash-free
opencode/ling-3.0-flash-fin-free
```

The production workflow will run the same command before generation and record the result. If the primary is unavailable, it reports that fact clearly before using a fallback.

Fallback is allowed only for model unavailability, rate limits, timeouts, or provider errors. A real writing or continuity failure is never hidden by switching models.

Use:

```text
NOVEL_MODEL=opencode/space-bunny-free
NOVEL_FALLBACK_MODELS=opencode/muse-spark-1.3-contributor-free,opencode/muse-spark-1.2-contributor-free,opencode/nemotron-3-ultra-free,opencode/nemotron-3.5-lightning-free,opencode/mimo-v2.6-flash-free,opencode/ling-3.0-flash-fin-free
```

## Chapter Length

Do not force a fixed count.

Use approximately 2,200–3,200 words for ordinary chapters. Allow shorter chapters for compact reversals and longer chapters for complete scenes, simulations, battles, or emotional payoffs. Never pad or split a complete scene solely to meet a number.

## State Growth

Never load the whole manuscript into every batch prompt. Keep summaries compact and bounded.

At the end of every batch:

- Store a batch summary.
- Keep a rolling window of 20–30 recent chapters for immediate voice reference.
- Update continuity and open threads.
- Keep a rolling volume summary.
- Archive older chapter summaries by volume without deleting them.

If the continuity files grow too large, create a volume-level index and retrieve only relevant sections.

## Security

Each public repository receives its own secret:

```text
OPENCODE_API_KEY
```

Use a separate key per repository. Never commit keys, print them, or send them to generated text.

Use least privilege, pinned actions, protected branches, and a dedicated bot identity. Do not use secrets-bearing workflows on untrusted pull requests.

## Approval Gates

Before any repository is created or pushed, review:

- `AGENTS.md`
- `RESEARCH.md`
- `NOVEL_CATALOG.md`
- `PHASE_SYSTEM.md`
- `REPO_PLAN.md`
- Primary and fallback model chain
- Public versus private draft policy
- Direct branch versus pull-request policy
- First five-repository pilot
