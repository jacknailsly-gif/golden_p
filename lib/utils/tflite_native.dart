// Stub implementation for TensorFlow Lite
// This provides fallback functionality when tflite_flutter is not available

class Interpreter {
  static Future<Interpreter> fromAsset(String assetName) async {
    throw UnsupportedError(
      'TensorFlow Lite is not available on this platform or due to compatibility issues',
    );
  }

  void run(List<dynamic> inputs, Map<int, dynamic> outputs) {
    throw UnsupportedError(
      'TensorFlow Lite is not available on this platform or due to compatibility issues',
    );
  }

  void close() {
    // No-op for stub
  }
}
