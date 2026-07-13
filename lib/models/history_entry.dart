class HistoryEntry {
  final String value; // The winner position (Gem)
  final String? selectedPos; // What the user/bot actually pressed (A, B, C)
  final String? actualBombPos; // Where the bomb was (A, B, C)
  final bool isRed;
  final int roundIndex;
  final double multiplier;
  final DateTime timestamp;

  HistoryEntry({
    required this.value,
    this.selectedPos,
    this.actualBombPos,
    this.isRed = false,
    required this.roundIndex,
    this.multiplier = 1.0,
    required this.timestamp,
  });
}
