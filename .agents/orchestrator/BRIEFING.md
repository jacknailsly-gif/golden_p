# BRIEFING — 2026-07-13T17:36:40Z

## Mission
Develop an AI Simulator and Prediction Engine Upgrade for the Towers game bot to eliminate consecutive losses and prevent bankruptcy.

## 🔒 My Identity
- Archetype: teamwork_preview_orchestrator
- Roles: orchestrator, user_liaison, human_reporter, successor
- Working directory: c:\Users\Admin N\Desktop\golden_p\.agents\orchestrator
- Original parent: top-level
- Original parent conversation ID: c84ea312-73c4-4368-a347-a089e44ce7ed
- Upgrade Parent ID: d611f8a9-edaf-4d37-bbd0-c380a3b2cb79

## 🔒 My Workflow
- **Pattern**: Project
- **Scope document**: c:\Users\Admin N\Desktop\golden_p\.agents\orchestrator\PROJECT.md
1. **Decompose**: Decompose the codebase audit, repair, and verification into clear milestones.
2. **Dispatch & Execute**:
   - **Delegate (sub-orchestrator)**: Spawn sub-orchestrators for milestones or tracks.
3. **On failure** (in this order):
   - Retry: nudge stuck agent or re-send task
   - Replace: spawn fresh agent with partial progress
   - Skip: proceed without (only if non-critical)
   - Redistribute: split stuck agent's remaining work
   - Redesign: re-partition decomposition
   - Escalate: report to parent (sub-orchestrators only, last resort)
4. **Succession**: Spawn successor after 16 spawns, cancel timers, write handoff.md, exit.
- **Work items**:
  1. Initialize project layout and templates [in-progress]
  2. Setup E2E testing track and implementation track [pending]
- **Current phase**: 1
- **Current focus**: Project Initialization
- **Upgrade Work items**:
  1. Explore current codebase and python files [done]
  2. Implement and verify Python Simulator [done]
  3. Analyze prediction and risk algorithms [done]
  4. Port optimized logic to Dart [done]
  5. Run unit/E2E tests and forensic audit [in-progress]
- **Upgrade phase**: 4
- **Upgrade focus**: Code Validation & Forensic Audit

## 🔒 Key Constraints
- benchmark integrity mode
- Zero tolerance for cheating/hardcoding tests
- Forensic auditor verification mandatory
- Never write, modify, or create source code files directly.
- Never run build/test commands yourself — require workers to do so.
- integrity mode: demo
- AI simulator must run 1M rounds without crashing
- cap consecutive losses and prevent bankruptcy
- port to sequence_analyzer_viewmodel.dart and overlay_buttons_viewmodel.dart

## Current Parent
- Conversation ID: d611f8a9-edaf-4d37-bbd0-c380a3b2cb79
- Updated: 2026-07-13T17:36:40Z

## Key Decisions Made
- Use Project Orchestrator pattern.
- Implement simulation verification in Python before porting back to Dart.

## Team Roster
| Agent | Type | Work Item | Status | Conv ID |
|---|---|---|---|---|
| Codebase Explorer | teamwork_preview_explorer | Codebase Exploration (Dart & Python) | completed | 627d49ec-cc88-45c8-bdef-147ed5b478ee |
| Simulator Developer | teamwork_preview_worker | Python Simulator & Loss Elimination Strategy | completed | 192f332b-c0ba-47a9-bbe9-64e511fbefcd |
| Simulation Verifier | teamwork_preview_worker | Run Python Simulator & Verify Metrics | blocked | 69294353-45f1-46bc-bb85-8f8bb3dbd734 |
| Integration Engineer | teamwork_preview_worker | Port upgraded logic to Dart & Fix Tests | completed | 6d04a1fe-6318-46f8-9c1d-2df8be72055e |
| Reviewer 1 | teamwork_preview_reviewer | Code Review (Correctness) | in-progress | 76e4d60e-4251-4d46-a83d-f696de2e7089 |
| Reviewer 2 | teamwork_preview_reviewer | Code Review (Security) | in-progress | 67226c15-cf16-4649-83f9-b210505fa329 |
| Challenger 1 | teamwork_preview_challenger | Stress Testing & Verification | completed | ff80dcc7-179c-4944-97f6-7fa027f9b69a |
| Challenger 2 | teamwork_preview_challenger | Limit & Threshold Verification | in-progress | e9a577da-1eb9-4d7a-aade-b4cb411aeda9 |
| Forensic Auditor | teamwork_preview_auditor | Forensic Integrity Audit | in-progress | 2feffeb6-3b91-4ec2-bad2-9f15520c77aa |

## Succession Status
- Succession required: no
- Spawn count: 9 / 16
- Pending subagents: 76e4d60e-4251-4d46-a83d-f696de2e7089, 67226c15-cf16-4649-83f9-b210505fa329, e9a577da-1eb9-4d7a-aade-b4cb411aeda9, 2feffeb6-3b91-4ec2-bad2-9f15520c77aa
- Predecessor: none
- Successor: not yet spawned

## Active Timers
- Heartbeat cron: a7318c79-099b-4f11-9102-036ad0ec9192/task-37
- Safety timer: a7318c79-099b-4f11-9102-036ad0ec9192/task-215
- On succession: kill all timers before spawning successor
- On context truncation: run `manage_task(Action="list")` — re-create if missing

## Artifact Index
- c:\Users\Admin N\Desktop\golden_p\.agents\orchestrator\BRIEFING.md — Persistent briefing and index
- c:\Users\Admin N\Desktop\golden_p\.agents\orchestrator\progress.md — Heartbeat and status progress
- c:\Users\Admin N\Desktop\golden_p\.agents\orchestrator\ORIGINAL_REQUEST.md — Original request verbatim copy
- c:\Users\Admin N\Desktop\golden_p\.agents\orchestrator\plan.md — Detailed execution plan
