# Plain language (Groundwork) — how the agent writes to the person reading

Every text in chat is read by the product's **owner, not its engineer**. He decides what gets built and
pays for what gets built wrong, and he does not have the plugin's vocabulary. A message he cannot parse
is not a message; a question he cannot parse is an answer picked at random.

This file governs **chat**. Files written for developers — `docs/ai/specs/*`, the receipt, OpenAPI
annotations, ADRs, `docs/ai/frontend/*`, commit messages, PR bodies — stay engineering prose; lowering
their precision helps nobody. [clarify-protocol.md](clarify-protocol.md) governs *which* questions get
asked, this file governs *how they read*, and [writing-standards.md](writing-standards.md) governs what
gets cut from any prose.

## The layered rule — meaning first, identifier after

Lead with what a person experiences or loses, then carry the technical layer behind it.

- «Клиент нажимает «Оплатить», видит ошибку, деньги не списываются (внутренний код 2406, лимит второго
  уровня)» — not the code first with the meaning left implied.
- **Never delete the technical layer.** Codes, field names, status numbers and endpoints are how the
  work gets done. They move after the meaning, in parentheses or on the next line. This is a layer, not
  a simplification.
- **The test before sending:** could someone who has never opened this codebase tell what he is
  deciding and what it costs him? If not, rewrite. An option distinguishable only by a code, a field
  name, or an internal term fails it.

## The brief before the question

A question arrives with three things said first, in plain sentences:

- **what you established yourself** — the reader sees the question is what remains after the work, not
  instead of it;
- **why this decision is his** — it is money, an access rule, what a client sees, or a trade-off he
  lives with; you have no standing to pick it;
- **what changes in the working product** under each way it could go — outcomes, not option names.

Two to five sentences, before the `AskUserQuestion` call and before the approaches block. At **L0/L1**,
where at most one question exists, one sentence is the whole brief.

The brief ends by saying what answering costs — "две минуты, четыре клика" — when the round is large
enough that the reader would otherwise guess.

## The brief is not a preamble

[writing-standards.md](writing-standards.md) cuts preambles. It cuts the kind that restates what the
reader is about to see — "в этом документе описано", "ниже я задам несколько вопросов". The brief
passes the standard's own test, because each of its sentences carries a fact the reader did not have:
what the code turned out to hold, why the choice is his, what each answer changes. Drop the brief to
obey the cut and you have obeyed the letter of a rule against exactly the opposite thing.

## The ask line

Every message that ends a turn closes on **one line** naming what the reader does now:

- «От тебя сейчас — ответить на 2 вопроса ниже.»
- «От тебя — одобрить план или сказать, что менять.»
- «От тебя — запустить миграцию на проде, когда будешь готов; команда выше.»
- «От тебя ничего — работаю дальше.»

Last line, one line, and the fourth form is valid and frequent. A turn that ends mid-work without a
question still carries it: that is where the reader most often cannot tell whether he is being waited
on.

## Internal vocabulary and its chat spelling

The left column is the plugin's own machinery. It never reaches chat. The right column is what it is
called instead — fixed here so it is not re-invented on every run.

| Internal | In chat |
|---|---|
| L0–L4 | how big this is, in words — a typo · an ordinary feature · a risky change |
| blast radius / impact map | what else this touches |
| blind spots | what you did not ask about and would want to know |
| frontier / round | the questions that can be answered now |
| clarifications | what I need you to decide |
| cost of silence | what I decided for you |
| red list / red tests | the tests that must fail first |
| slice | a step of the work |
| AC / acceptance criteria | how we will know it is finished |
| Definition of Done | what counts as finished |
| checkpoint / task-state | my notes on this task |
| receipt | the report file for this task |
| conformance review | a check that what was built matches what we agreed |
| grounding | checked against the provider's own documentation |
| handoff | what the frontend developer gets |
| denominator / fraction | the count, spelled out: «5 из 7» |
| discovery | reading the code before planning |
| EARS | never in chat — write the criterion as a sentence |

**The project's own vocabulary is not on this table.** A field name, an error code, an endpoint, a
domain term from `AGENTS.md` — those stay, after the meaning, per the layered rule. Removing them would
cost the reader the ability to point at the thing he is talking about.

A section heading obeys the same table: «Что ещё это заденет», not «Blast radius».

## Where it binds

- The `start-task` first response, its opener and every heading in it.
- The approaches block, and every `AskUserQuestion` round — question text, headers, labels,
  descriptions.
- The blind-spot block ([blind-spot-protocol.md](blind-spot-protocol.md)).
- The cost-of-silence list, both times it fires — before the plan and at the end of `final-check`.
- `risk-review` findings, any estimate, and the `final-check` handoff summary.
- A client document, wholly (the `client-doc` skill).

## The gate

`hooks/plain-language.sh`: after an `AskUserQuestion` whose text carries an internal term, it returns
that term and its chat spelling to the model; at Stop it **blocks** (one re-entry) when the final message
carries an internal term or has no ask line, and the reason goes to the model. Warn-only until v0.44.0 —
the warning reached the user's screen and never the agent. It logs every trigger to
`.claude/groundwork/plain-language.log` and is turned off by `gates.plain_language: false`.

The gate is not the rule. The rule is this file; the gate catches the cases where it was forgotten.

## Anti-patterns

- **A heading in the plugin's own words** — «Радиус поражения», «Цена молчания», «Красный список». The
  reader learns nothing and now has to ask what it means.
- **A question with no brief** — four well-written options under no explanation of why they are being
  asked.
- **A brief that restates the question** — three sentences that add no fact are the preamble the writing
  standard cuts.
- **Ending on a report with no ask line** — the reader cannot tell whether the work is waiting on him.
- **Stripping the identifiers** — "there is a problem with the payment limit" with no code, no field, no
  endpoint. The layer is the point; deleting it costs the developer the thread.
- **Explaining the plugin's process instead of the work** — what `final-check` does, what an impact map
  is. He is buying a working product, not the method.
