import re

with open("lib/viewmodels/overlay_buttons_viewmodel.dart", "r", encoding="utf-8") as f:
    content = f.read()

# 1. Fix maxRecoveryStepsThisCycle to always be 1
content = re.sub(
    r"int maxRecoveryStepsThisCycle = 2;.*?\n  }",
    """int maxRecoveryStepsThisCycle = 1;
  double savedScrollY = 0.0;

  int randomizeRecoveryQuota({int? fixedForTest}) {
    maxRecoveryStepsThisCycle = 1;
    return 1;
  }""",
    content,
    flags=re.DOTALL
)

# 2. Fix _detectVisualOutcome condition order
# We want to check `consecutiveLossesStreak >= 3` BEFORE `observationRoundsRemaining > 0`
content = content.replace('''
          if (state.observationRoundsRemaining > 0) {
            state.observationRoundsRemaining--;
''', '''
          if (state.consecutiveLossesStreak >= 3) {
            // FORCE OBSERVATION IMMEDIATELY! Do not let it process observation decrement!
            state.recoveryStepInCycle = 0;
            state.isLossStreakBaseBetLocked = true;
            state.isCurrentlyRecoveryRound = false;
            final int obsRounds = state.generatePostLossObservationRounds(isPostObservationLoss: false);
            state.observationRoundsRemaining = state.observationRoundsRemaining > obsRounds ? state.observationRoundsRemaining : obsRounds;
            state.currentRecoveryCycle = 2;
            transitionRecoveryState(mode, RecoveryState.observation, reason: 'Normal Base Bet lost 3 consecutive times -> FORCE Observation');
            // We set it above, so the next if block will decrement it once for this round!
          }

          if (state.observationRoundsRemaining > 0) {
            state.observationRoundsRemaining--;
''')

# 3. Remove the old `else if (state.consecutiveLossesStreak >= 3)` block since we moved it up.
content = re.sub(
    r"\} else if \(state\.consecutiveLossesStreak >= 3\) \{.*?await _ensureBaseBet\(runToken, mode: mode\);",
    "} else if (false) {",
    content,
    flags=re.DOTALL
)


with open("lib/viewmodels/overlay_buttons_viewmodel.dart", "w", encoding="utf-8") as f:
    f.write(content)
