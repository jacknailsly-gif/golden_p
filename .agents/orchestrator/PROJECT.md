# Project: Towers AI Simulator & Prediction Engine Upgrade

## Architecture
- `lib/viewmodels/sequence_analyzer_viewmodel.dart` - Analyzes history sequences and produces predictions.
- `lib/viewmodels/overlay_buttons_viewmodel.dart` - Drives automated execution, bet sizes, dynamic adjustments.
- `lib/services/prediction_pipeline_service.dart` - Orchestrates the sub-engines/models.
- `lib/utils/model.py` and `lib/utils/server.py` - Core Python services or helper classes.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Codebase Exploration | Explore current Dart viewmodels, Python files, and existing tests. | None | DONE (627d49ec-cc88-45c8-bdef-147ed5b478ee) |
| 2 | Python Simulator Implementation | Implement a Python simulation script modeling the Towers game and Casino Trap Seed, running 1M rounds. | M1 | DONE (192f332b-c0ba-47a9-bbe9-64e511fbefcd) |
| 3 | Loss Elimination Strategy | Design prediction algorithms and strict risk management to prevent consecutive losses/bankruptcy in Python. | M2 | DONE (69294353-45f1-46bc-bb85-8f8bb3dbd734) |
| 4 | Dart Porting & Integration | Port logic to sequence_analyzer_viewmodel.dart and overlay_buttons_viewmodel.dart. | M3 | DONE (6d04a1fe-6318-46f8-9c1d-2df8be72055e) |
| 5 | Validation & Audit | Run tests (`flutter test`), build application, and run Forensic Integrity Audit. | M4 | IN_PROGRESS (Reviewers, Challengers, Auditor) |

## Interface Contracts
### SequenceAnalyzerViewModel ↔ OverlayButtonsViewModel
- SequenceAnalyzerViewModel analyzes history sequences and produces predictions.
- OverlayButtonsViewModel handles automated click decisions, bet amounts, recovery states, and stop-loss logic.
