import 'dart:math';
import 'package:crypto/crypto.dart';
import 'dart:convert';

void main() {
  int a = 0, b = 0, c = 0;
  var random = Random();
  String serverSeed = Iterable.generate(64, (_) => '0123456789abcdef'[random.nextInt(16)]).join();
  String clientSeed = Iterable.generate(24, (_) => '0123456789abcdef'[random.nextInt(16)]).join();
  
  for (int i = 0; i < 1000; i++) {
    String message = '$clientSeed:$i:0';
    var key = utf8.encode(serverSeed);
    var bytes = utf8.encode(message);
    var hmacSha256 = Hmac(sha256, key);
    var digest = hmacSha256.convert(bytes);
    List<int> hashBytes = digest.bytes;
    int chunk = (hashBytes[0] << 24) | (hashBytes[1] << 16) | (hashBytes[2] << 8) | hashBytes[3];
    double roll = (chunk >>> 0) / 4294967296.0;
    int position = (roll * 3).floor();
    
    if (position == 0) a++;
    else if (position == 1) b++;
    else if (position == 2) c++;
    else print("UNKNOWN POSITION: $position, roll: $roll, chunk: $chunk");
  }
  print("A: $a, B: $b, C: $c");
}
