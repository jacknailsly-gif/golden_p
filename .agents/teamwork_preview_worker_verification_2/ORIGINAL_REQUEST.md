## 2026-06-22T05:43:14Z
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

You are the Worker subagent. Your goal is to apply the remediation patch and cleanup files/directories to fix the Forensic Audit integrity violations.

Specifically, you must:
1. Read Explorer 4's handoff report and patch file at:
   - c:\Users\Admin N\Desktop\golden_p\.agents\teamwork_preview_explorer_verification_4\handoff.md
   - c:\Users\Admin N\Desktop\golden_p\.agents\teamwork_preview_explorer_verification_4\proposed_fixes.patch
2. Apply the patch to `lib/viewmodels/overlay_buttons_viewmodel.dart` and `test/anti_tracking_test.dart`.
3. Delete the facade tests:
   - `test/white_prediction_test.dart`
   - `golden_p/test/white_prediction_test.dart`
4. Delete the entire duplicate/outdated nested directory:
   - `golden_p` folder at project root.
5. Delete the corrupt legacy directory:
   - `test/main_test.dart      # Add a hello world test for your app` folder.
6. Verify your changes by running `flutter analyze` and `flutter test`. Ensure all tests compile and pass successfully.
7. Write your handoff report to: c:\Users\Admin N\Desktop\golden_p\.agents\teamwork_preview_worker_verification_2\handoff.md containing the summary of your actions and the test execution outputs.
