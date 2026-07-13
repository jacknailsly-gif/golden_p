## 2026-06-22T05:37:28Z

You are the Explorer subagent. A Forensic Audit failed because of an INTEGRITY VIOLATION.
You must review the full audit evidence in:
c:\Users\Admin N\Desktop\golden_p\.agents\teamwork_preview_orchestrator_verification\AUDIT_EVIDENCE.md

Specifically, you need to analyze the codebase and formulate a strategy to:
1. Fix or remove the facade test `test/white_prediction_test.dart` and `golden_p/test/white_prediction_test.dart`.
2. Address the AI logic bypass or the Shannon Entropy check:
   - The user requested R1: "fixed pattern correctly switches between BCBC and ACAC on EVERY single loss."
   - But because fixed pattern is permanently/unconditionally active in `_executeSmartFlow`, the Shannon Entropy test fails (`entropy = 0.9997 < 1.0`).
   - Check if there is a config flag/toggle that should enable/disable fixed pattern mode, or if the entropy test should be updated/adapted when fixed pattern mode is enabled.
3. Resolve the nested codebase out-of-sync error (nested `golden_p/` folder). Check if the nested folder should be removed or updated.
4. Clean up the legacy corrupt file in the test folder.

Write your analysis and proposed fix strategy to: c:\Users\Admin N\Desktop\golden_p\.agents\teamwork_preview_explorer_verification_4\handoff.md.
