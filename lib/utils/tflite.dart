// This file acts as a conditional exporter for TFLite implementations.
// It exports the native implementation for platforms that support dart:io,
// and the stub implementation for others (like web).

export 'tflite_stub.dart' if (dart.library.io) 'tflite_native.dart';
