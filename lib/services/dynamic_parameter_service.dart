import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:golden_p/engines/provably_fair_engine.dart';
import 'package:golden_p/services/prediction_pipeline_service.dart';
import 'package:path_provider/path_provider.dart';

class DynamicParameterService {
  static final DynamicParameterService _instance = DynamicParameterService._internal();
  factory DynamicParameterService() => _instance;
  DynamicParameterService._internal();

  /// Loads optimized_params.json from external storage and applies it.
  Future<void> reloadParameters(ProvablyFairEngine? pfEngine, PredictionPipelineService pps) async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      
      final file = File('${dir.path}/optimized_params.json');
      if (!await file.exists()) {
        debugPrint('[V124] ⚠️ No dynamic parameters found at ${file.path}');
        return;
      }

      final jsonStr = await file.readAsString();
      final Map<String, dynamic> params = jsonDecode(jsonStr);

      debugPrint('[V124] 🔄 Reloading dynamic parameters from AI Trainer...');

      // Update ProvablyFairEngine if present
      if (pfEngine != null) {
        if (params.containsKey('bomb_history_window')) {
          pfEngine.maxBombHistory = params['bomb_history_window'];
        }
        if (params.containsKey('loss_history_window')) {
          pfEngine.maxLossHistory = params['loss_history_window'];
        }
        if (params.containsKey('hmac_threshold')) {
          pfEngine.hmacThreshold = (params['hmac_threshold'] as num).toDouble();
        }
      }

      // Update PredictionPipelineService
      if (params.containsKey('memory_decay_rate')) {
        pps.memoryDecayRate = (params['memory_decay_rate'] as num).toDouble();
      }
      if (params.containsKey('prediction_penalty')) {
        pps.predictionPenalty = (params['prediction_penalty'] as num).toDouble();
      }
      if (params.containsKey('prediction_reward')) {
        pps.predictionReward = (params['prediction_reward'] as num).toDouble();
      }
      if (params.containsKey('vote_noise_max')) {
        pps.voteNoiseMax = (params['vote_noise_max'] as num).toDouble();
      }
      if (params.containsKey('v70_inversion_streak')) {
        pps.v70InversionStreak = params['v70_inversion_streak'];
      }
      if (params.containsKey('deep_history_window')) {
        pps.deepHistoryWindow = params['deep_history_window'];
      }
      if (params.containsKey('vote_weight_floor')) {
        pps.voteWeightFloor = (params['vote_weight_floor'] as num).toDouble();
      }

      debugPrint('[V124] ✅ Parameters updated successfully!');
    } catch (e) {
      debugPrint('[V124] ❌ Failed to reload dynamic parameters: $e');
    }
  }
}
