# Novel Fleet Agent Instructions

## Mission

Create original, publishable male-led webnovels with strong long-form engines, natural prose, earned progression, mystery, character relationships, complete volume arcs, and planned endings.

The writing must feel like finished fiction, not an outline, chapter summary, prompt transcript, or technical manual.

## Prose

- Write complete scenes with physical space, action, sensory detail, dialogue, subtext, character thought, and emotional consequence.
- Use natural paragraphs, generally two to six sentences. Use a one-line paragraph only when it is a deliberate dramatic beat.
- Never replace a scene with a list of actions, states, checks, or beats.
- Vary sentence length and paragraph rhythm. Do not repeat words such as held, steady, plain, counted, breathed, wrote, and nodded as mechanical filler.
- Show information through character action, conversation, work, and consequences. Do not deliver lore lectures.
- Let important moments breathe. Do not rush a confrontation, reveal, death, recovery, or emotional decision.
- Use grounded sensory detail without overloading every paragraph with ornate description.
- Keep the prose accessible. Avoid inflated fantasy diction, artificial technical language, and constant purple prose.

## Chapter Structure

Every chapter should contain:

1. A beginning that continues existing pressure or introduces immediate action.
2. A character goal that can be stated clearly.
3. Resistance from another character, the world, the past, or the protagonist's own limitations.
4. A meaningful change caused by the scene.
5. A completed emotional or practical beat.
6. An ending that creates a new question, decision, threat, revelation, or consequence.

Not every chapter needs a cliffhanger. A good ending may be a decision, a cost, a reversal, a discovery, or an emotional shift. Never manufacture suspense by cutting away in the middle of a sentence or action.

## Batch Writing

A workflow phase normally writes 10 to 20 chapters in one run. The default pilot is 10 chapters. The model is loaded once for the batch.

Before writing a batch, read:

- The complete series outline and ending.
- The current volume outline.
- The current batch chapter cards.
- The previous 20 chapters for immediate voice and continuity; extend to 30 when the model’s verified context budget safely allows it.
- `state/current.md`.
- `state/continuity.md`.
- `state/open-threads.md`.
- Relevant character and world files.

Do not load the entire manuscript into every prompt. Use rolling summaries and a volume index for long-range memory.

Write chapters in order. Do not restart a completed chapter. If an output limit is reached, stop at a chapter boundary, save the completed chapters and state, mark the remaining batch as resumable, and continue in the next run.

After the batch, update the batch summary, chapter summaries, continuity, open threads, character state, and phase ledger. Keep summaries compact and useful for the next batch. Preserve the planned ending and do not introduce a new final enemy without flagging it.

After completing a batch, inspect the current volume outline. If more chapters remain, create exactly one next batch directory and detailed prompt. If the volume is complete, create exactly one volume-close prompt. Do not create more than the next phase.

## Serial Pacing

Use four pacing levels:

- Chapter: one complete scene with movement and a changed situation.
- Mini-arc: usually three to eight chapters, containing a promise, escalation, turn, and payoff.
- Batch: usually 10 to 20 chapters, containing a batch goal, midpoint, escalation, and batch-level climax.
- Volume: usually 40 to 80 chapters, with a distinct central pressure and a real resolution.

A volume must close its immediate promise even while opening a larger question. Do not delay every answer until the end of a 500-chapter series.

Alternate pressure types: action, mystery, character conflict, training, political pressure, emotional consequence, discovery, and recovery. Do not make every chapter another fight or another System notification.

## Male Leads and Relationships

All primary protagonists are male.

Give the lead a believable inner life, flaws, habits, work, relationships, and changing responsibilities. Strength should not erase his personality.

Use one slow-burn relationship or no romance by default. Do not use harem structures unless a novel is explicitly approved for them. Relationships must develop through choices, conflict, trust, and consequence rather than instant attraction.

## Real-World Characters

Prefer fictional characters with realistic lives and pressures: teachers, engineers, doctors, train drivers, shopkeepers, farmers, police, journalists, students, mechanics, civil servants, and caregivers.

Do not use private real people as fictional characters without permission. Do not use living public figures as caricatures or put invented controversial statements in their mouths.

## Systems

A System should be understandable to the reader and fit the fictional world.

- Use plain language inside System messages.
- Prefer short, concrete prompts over technical specifications.
- Use at most one System panel per chapter unless the story specifically depends on multiple panels.
- Let the System be incomplete, biased, limited, or misunderstood.
- Do not spam the reader with statistics, item names, skill tables, or artificial terminology.
- A System may provide a rule, warning, choice, or consequence, but the protagonist must still act.
- Avoid real software jargon such as API, protocol, backend, runtime, token, latency, and deployment unless the setting deliberately uses it and the language remains natural.
- A number should matter because of what it changes in the story, not because the number exists.

## Simulation and Player-World Stories

A simulation is not a disposable excuse for rapid-fire summaries.

Every simulation or player arc must have:

1. Entry conditions.
2. A world with its own rules, history, geography, factions, and ordinary life.
3. A beginning objective.
4. Complications that arise from the world and characters.
5. Escalating pressure.
6. A major choice or reversal.
7. A climax with consequences.
8. An aftermath that changes the real world, the protagonist, or the next simulation.

Do not rush through an entire world in a few chapters. Let players form relationships, make mistakes, exploit rules, misunderstand the world, and disagree about what is happening.

If Earth players believe they are entering a game, show real human behavior: skepticism, greed, cooperation, grief, farming, crafting, theorycrafting, romance, administrative confusion, and arguments about whether the world is real.

## Ending and World-Building

Plan the ending before drafting the first chapter. The ending may remain unrevealed to the reader, but the author must know:

- The final external conflict.
- The protagonist's final choice.
- The final emotional and philosophical answer.
- Which relationships survive or change.
- What the world looks like afterward.
- Which mysteries are fully answered and which remain intentionally open.

Build the world through layers:

1. Immediate physical survival and local work.
2. Factions, families, professions, and ordinary routines.
3. Regional history and competing explanations.
4. The power system's origin and costs.
5. Cross-regional politics and trade.
6. The final historical and moral conflict.

Do not dump the entire world in the opening. Let each volume reveal a deeper layer while preserving earlier rules.

## Originality and Research

Research genre conventions, not individual prose. Do not imitate a living author, reproduce passages, copy distinctive character voices, or recreate a protected plot scene-for-scene.

Use research to identify broad patterns such as weak-to-strong progression, mystery, earned power, volume structure, and serial pacing. Every novel must have its own premise, world, power system, character network, and central mystery.

## Continuity Workflow

Before writing a batch, read the series ending, volume outline, batch cards, rolling summary, previous batch summary, immediate previous chapters, current state, active character files, and open-thread file.

After writing, update all state files and record any proposed canon change. Do not silently invent a fact that changes the world's rules.

## Quality Gate

A batch is not complete because files exist. It is complete only when:

- Every planned chapter exists and is finished prose.
- Every chapter changes the situation.
- The prose reads as natural fiction rather than an outline.
- Characters act from motive rather than plot convenience.
- Setting and power rules remain consistent.
- The batch midpoint and climax occur.
- No meta language or duplicated paragraphs remain.
- The ending creates earned forward pull.
- State and summaries are updated.
- A reviewer has checked the result.
- The planned volume direction remains intact.
