// import 'package:isar/isar.dart';
// import 'package:path_provider/path_provider.dart';
// import 'collections/prediction_history.dart';
// 
// class IsarService {
//   late Future<Isar> db;
// 
//   IsarService() {
//     db = openDB();
//   }
// 
//   Future<Isar> openDB() async {
//     if (Isar.instanceNames.isEmpty) {
//       final dir = await getApplicationDocumentsDirectory();
//       return await Isar.open(
//         [PredictionHistorySchema],
//         directory: dir.path,
//         inspector: true,
//       );
//     }
//     return Future.value(Isar.getInstance());
//   }
// 
//   Future<void> savePrediction(PredictionHistory history) async {
//     final isar = await db;
//     await isar.writeTxn(() async {
//       await isar.predictionHistorys.put(history);
//     });
//   }
// 
//   Future<List<PredictionHistory>> getAllHistory() async {
//     final isar = await db;
//     return await isar.predictionHistorys.where().sortByTimestampDesc().findAll();
//   }
// }
