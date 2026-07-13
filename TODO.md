TODO: Repository-wide task tracker

- High priority (must fix before release):
  - [ ] Android app: Replace hard-coded applicationId with a property-driven value and add a secure release signing config.
  - [ ] Android: Wire signingConfig.release to read keystore details from environment/local properties (APP_ID, KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD).

- Medium priority:
  - [ ] Remove or clarify TODOs in generated/dependency files (eg. in build/mapping configuration) or move to ephemeral config as appropriate.
  - [ ] Windows/Linux Flutter CMakeLists.txt: decide whether to move remaining TODOs into ephemeral config or remove if not needed.

- Low priority:
  - [ ] Clean up sample TODO hooks in .git/hooks if not used (sendemail-validate.sample).

- Plan: Maintain a living document of todos to make triage predictable and to avoid stale TODOs in source.
