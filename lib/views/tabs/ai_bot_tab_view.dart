import 'package:flutter/material.dart';
import 'package:golden_p/views/sequence_analyzer_view.dart';

class AIBotTabView extends StatelessWidget {
  const AIBotTabView({super.key});

  @override
  Widget build(BuildContext context) {
    // Return the actual SequenceAnalyzerView which has its own Scaffold and real buttons.
    // Removed the fake AppBar (AI Bot, Start) and fake FloatingActionButtons (Pause, Settings, Info).
    return const SequenceAnalyzerView();
  }
}
