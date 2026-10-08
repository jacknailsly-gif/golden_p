import 'dart:math';

enum GameMode {
  towers,
  mines,
}

extension GameModeExtension on GameMode {
  String get displayName {
    switch (this) {
      case GameMode.towers:
        return 'Towers';
      case GameMode.mines:
        return 'Mine';
    }
  }

  String get fullTitle {
    switch (this) {
      case GameMode.towers:
        return 'Midnight Azure Towers';
      case GameMode.mines:
        return 'Polpick.io - Gems';
    }
  }

  String get defaultUrl {
    switch (this) {
      case GameMode.towers:
        return 'https://faucetpay.io/play/towers';
      case GameMode.mines:
        return 'https://polpick.io/gems.php';
    }
  }

  String get storagePrefix {
    switch (this) {
      case GameMode.towers:
        return 'towers';
      case GameMode.mines:
        return 'mines';
    }
  }

  /// Calculates dynamic base bet based on the active balance
  /// - Towers: Balance / 10,000 (Min: 0.00007882 DOGE, 0.00000903 POL, 0.000005 USDT, 0.00171871 FEY, 0.3859 PEPE, 0.000743 DGB)
  /// - Mine (Polpick): Balance / 10,000 (Min: 0.00001, 0.000005 USDT)
  double calculateBaseBet(double balance, double? floorLimit, {String? coin}) {
    final String c = (coin ?? 'DOGE').toUpperCase().trim();
    final double defaultFloor = (c == 'USDT' || c == 'TETHER')
        ? 0.000005
        : (this == GameMode.mines
            ? 0.00001
            : ((c == 'POL' || c == 'POLYGON' || c == 'MATIC')
                ? 0.00000903
                : (c == 'FEY' || c == 'FEYORRA')
                    ? 0.00171871
                    : (c == 'PEPE')
                        ? 0.3859
                        : (c == 'DGB' || c == 'DIGIBYTE')
                            ? 0.000743
                            : 0.00007882));

    final double minFloor = floorLimit != null && floorLimit > 0
        ? max(floorLimit, defaultFloor)
        : defaultFloor;

    if (balance <= 0) {
      return minFloor;
    }

    final double calculated = balance / 10000.0;
    return max(calculated, minFloor);
  }
}
