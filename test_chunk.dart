void main() {
  List<int> hashBytes = [255, 255, 255, 255];
  int chunk = (hashBytes[0] << 24) | (hashBytes[1] << 16) | (hashBytes[2] << 8) | hashBytes[3];
  print("chunk: $chunk");
  double roll = (chunk >>> 0) / 4294967296.0;
  print("roll: $roll");
  
  hashBytes = [128, 0, 0, 0];
  chunk = (hashBytes[0] << 24) | (hashBytes[1] << 16) | (hashBytes[2] << 8) | hashBytes[3];
  print("chunk: $chunk");
  roll = (chunk >>> 0) / 4294967296.0;
  print("roll: $roll");
}
