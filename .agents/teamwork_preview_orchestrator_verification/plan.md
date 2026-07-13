# Verification & Remediation Plan: Towers Game Bot Logic Changes (V68.0 and V69.0)

## Objective
Verify and correct any logical errors, edge cases, or runtime crashes in the Towers game bot. Ensure all tests compile and pass successfully, and remediate all Forensic Audit integrity violations.

## Milestones

### Milestone 1: Exploration & Code Review Audit
- **Status**: DONE (Audits completed across Iteration 1 and Iteration 2)
- **Findings**:
  - Legacy facade tests `test/white_prediction_test.dart` and `golden_p/test/white_prediction_test.dart` exist but reference non-existent helper methods. They must be deleted.
  - The unconditional fixed pattern bypasses the AI pipeline, causing the Shannon Entropy test in `test/anti_tracking_test.dart` to fail. We will make it conditional using a toggle `_isFixedPatternEnabled`.
  - The nested folder `golden_p` contains outdated views and viewmodels causing compilation/runtime conflicts. It must be deleted.
  - The corrupt test folder `test/main_test.dart      # Add a hello world test for your app` must be deleted.

### Milestone 2: Remediation Implementation & Verification
- **Goal**: Implement the remediation patch and delete the flagged legacy/duplicate folders and files. Ensure all tests pass.
- **Agent**: `teamwork_preview_worker` (Fresh spawn)
- **Verification Command**: `flutter analyze` and `flutter test`
- **Output**: Clean compiler output and 100% passing tests.

### Milestone 3: Independent Review & Final Sign-off
- **Goal**: Run independent reviews, adversarial checks, and forensic audit to guarantee compliance and clean status.
- **Agents**: `teamwork_preview_reviewer` (2), `teamwork_preview_challenger` (2), `teamwork_preview_auditor` (1)
- **Output**: Verified test reports, reviewer sign-offs, and clean audit report.
