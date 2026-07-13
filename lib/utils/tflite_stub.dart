// Stub implementation for TensorFlow Lite when the package is not available
// This provides fallback functionality when tflite_flutter has compatibility issues

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
