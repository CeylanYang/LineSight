# LineSight — Weekly Work and Contribution Tracker

> Living record for weekly planning, practice, evidence, and individual contributions. Update task status and evidence after each work session; keep decisions and their rationale so later reports can reuse this record.

## Project baseline

- **Project:** LineSight, a production-line inspection HMI concept and software prototype.
- **Team:** 7 people, organized as working groups of 3, 2, and 2. Names and individual ability profiles have not been supplied here; assign named owners before claiming individual contributions.
- **Last week's focus (as reported by the team):** user interaction/UI design, using Figma and Pixso. The Week 4 course brief also asks Draft 1 to show the development trail **notes → hand sketches → Visily wireframes → Figma edits → Pixso prototype**. Add Visily evidence if it was used; do not imply it was used if it was not.
- **Current focus:** hands-on stack exploration and a reasoned, recorded technology-stack decision.
- **Week 4 app prototype update (2026-10-07):** a Flutter UI spike now implements the Home, Modules, PR inspection-history, and Profile screens. It was built and launched on an Android 16 (API 36) emulator. Evidence: `../lib/main.dart`, `../screenshots/android-home.png`, and `../design/svg-redraw/`. This implementation is a technical prototype; the team's formal stack decision remains open until recorded below.
- **Current source documents:** `../week2/LineSight_Week2_Deliverable.md` (existing concept, UI, event model, and provisional build architecture); `../ENT207TC Week 4 From prototype to build.pdf` (Week 4 session tasks); `../ability.txt` (team capability reference).
- **Status convention:** `Not started` / `In progress` / `Done` / `Blocked`. A task is Done only when its evidence is linked or named below.

## Week 4 — Thursday session and follow-through

| Workstream | Practice to perform | Required evidence / output | Suggested owner pattern (3/2/2) | Status |
|---|---|---|---|---|
| Mentor checkpoint | Rehearse and present the problem, target user, one-sentence solution, and three features through the Pixso prototype. Assign a presenter, demo driver, and note-taker; other members record unanswered questions. | Prototype walkthrough; verbatim mentor feedback; unanswered questions; three agreed priority changes in this week's log. | Group of 3: presenter, demo driver, note-taker. Both pairs attend and capture questions/observations. | Not started |
| Draft 1 evidence trail | Assemble the problem, who has it, target user, size/importance with light research and citations, and solution walkthrough. Gather evidence for each actual design stage. | Draft 1 outline and linked screenshots/photos in the sequence notes → sketches → Visily → Figma → Pixso, with absent stages labelled honestly. Incorporate the three priority feedback changes. | Pair 1: problem/user and research evidence. Pair 2: design-stage artefacts. Group of 3: assemble narrative and check consistency. | Not started |
| Stack decision | Compare and choose a tool for each layer: app builder, database, backend logic, users/login, and AI feature (API expected in Week 6). Explain why each choice fits LineSight and note constraints/risks. | Completed stack decision table in Weekly Log; decision rationale, alternatives considered, owner for each layer, open questions, and a Kanban card per build task. | Group of 3: prototype/build feasibility. Pair 1: compare one free alternative (e.g. Bolt.new, Lovable, Base44). Pair 2: map data, workflow, authentication, and AI boundaries. Share findings and decide together. | Not started |
| Individual tool practice | Each member creates a Softr account, begins the free certification, and practises the relevant builder workflows. If the team chooses Softr, allocate up to three workspace builder seats; other members practise in individual accounts. | Account/certification progress recorded per person; short notes on what was learned, attempted, confusing, or fixed. Do not claim certification until passed. | All 7 members individually; up to 3 named builders if Softr is selected. | Not started |
| Weekly learning log | Record friction, errors, attempted fixes, and what each person learned. Use AI/documentation as a lab partner and preserve the actual question/attempt/result where useful. | Dated individual entries and links/screenshots to practice evidence. | All 7 members. | Not started |
| Kanban and next build | Translate stack layers and unresolved work into owned, actionable cards. | Board reflects owner, next action, and status; retain board history or dated screenshot. | One coordinator from the group of 3; every owner updates their cards. | Not started |

### Stack decision record (fill after practice)

| Layer | Decision | Why this fits LineSight | Alternative tested / rejected and why | Owner | Evidence / open issue |
|---|---|---|---|---|---|
| App builder | TBD | TBD | TBD | TBD | TBD |
| Database | TBD | TBD | TBD | TBD | TBD |
| Backend logic / workflows | TBD | TBD | TBD | TBD | TBD |
| Users and login | TBD | TBD | TBD | TBD | TBD |
| AI feature and Week 6 API boundary | TBD | Define the user input, expected output, and where the API call belongs. | TBD | TBD | API is expected in Week 6; confirm implementation details when provided. |

**Working hypothesis already in the project report:** React + TypeScript/Vite for the front end, Python for simulated inference/workflows/sync, SQLite for the event store, and GitHub for version control and delivery tracking. Treat this as a candidate architecture to validate against the course's no/low-code options, team skills, required features, free-tier limits, and time—not as the Week 4 decision until the team has tested and recorded its reasoning.

The Week 4 slides state Softr is the proposed route and list Bolt.new, Lovable, and Base44 as allowed alternatives. They also state that free-tier limits can change. Check current limits before relying on them, and do not enter payment details during the free-tool exploration.

## Contribution capture

Write contributions from completed, evidenced work. Use this pattern:

> **[Name]** practised **[specific action/tool]** to address **[project need]**, produced **[artifact or decision]**, and documented **[learning, trade-off, or next step]**. Evidence: **[link/file/screenshot/board card]**.

Avoid describing planned work as completed. For group contributions, identify who did which part and how the work affected the product or team decision.

| Person | Practice completed | Concrete output | What changed / was learned | Evidence | Contribution statement ready? |
|---|---|---|---|---|---|
| chaoyang | TBD | TBD | TBD | TBD | No |
| KrOik | TBD | TBD | TBD | TBD | No |
| Member 3 | TBD | TBD | TBD | TBD | No |
| Member 4 | TBD | TBD | TBD | TBD | No |
| Member 5 | TBD | TBD | TBD | TBD | No |
| Member 6 | TBD | TBD | TBD | TBD | No |
| Member 7 | TBD | TBD | TBD | TBD | No |

### Contribution evidence to collect

- Prototype demo and dated screenshots of the screens actually shown.
- Mentor feedback captured accurately, unanswered questions, and the three selected changes.
- Draft 1 sources/citations and design-stage artefacts, with dates and authors where known.
- Stack comparison notes, trial screenshots or links, decision rationale, and named layer owners.
- Individual tool practice notes, errors and fixes, and certification progress.
- Kanban cards/history and dated Weekly Log entries.

## Explicitly known vs. still to confirm

### Explicitly known from current materials and team instructions

- The project report identifies the product as LineSight and specifies a five-screen, touch-first HMI concept, an inspection event model, and a provisional software architecture.
- The team's stated prior focus is user interaction/UI design with Figma and Pixso; the Week 4 class brief specifies a fuller Draft 1 evidence sequence that also includes notes, sketches, and Visily wireframes.
- The Thursday session expects a mentor prototype demo, feedback capture, Draft 1 preparation, hands-on stack exploration, a stack decision in the Weekly Log, initial Kanban build tasks, and individual contribution records.
- The stack decision should cover app builder, database, backend/workflows, users/login, and AI feature/API boundary.
- The Week 4 brief asks everyone to create a Softr account and begin certification; it suggests scouts test an alternative and builders use up to three shared workspace seats if Softr is selected.
- The ability reference lists communication, critical thinking, leadership, professionalism, teamwork, technology use, and self-development capabilities. It does not identify which named student has which ability.

### Still to confirm / capture during practice

- Names and actual membership of the 3/2/2 working groups, and named task owners.
- Which design stages/tools were actually used last week, and where their dated evidence is stored.
- Mentor feedback, selected changes, and whether they are incorporated into Draft 1.
- Which stack was selected after hands-on comparison, the evidence behind that choice, and current free-tier constraints.
- Individual practice outcomes, errors/fixes, certification progress, and contribution evidence.
- Exact Week 5 session/submission date; the course brief says Draft 1 is due no later than one day before that session.

## Next update

After Thursday, replace `Not started` with evidence-backed statuses, complete the decision record, add each person's contribution entry, and carry unresolved tasks into the next week's section. Preserve earlier decisions and add dated amendments when a choice changes.
