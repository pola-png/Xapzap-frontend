import 'package:appwrite/appwrite.dart' show Query;
import 'package:appwrite/models.dart' as models;

import 'appwrite_service.dart';

class BoostService {
  static const double baseReachPerDollarPerDay = 5000.0;

  static int computeTargetReach(double amountUsd, int days) {
    if (amountUsd <= 0 || days <= 0) return 0;
    return (amountUsd * days * baseReachPerDollarPerDay).round();
  }

  static Future<models.Row> createDraftBoost({
    required String postId,
    required double amountUsd,
    required int days,
  }) async {
    final user = await AppwriteService.getCurrentUser();
    if (user == null) {
      throw StateError('User must be signed in to boost posts.');
    }
    final targetReach = computeTargetReach(amountUsd, days);
    final data = <String, dynamic>{
      'postId': postId,
      'userId': user.$id,
      'status': 'pending',
      'amountUsd': amountUsd,
      'days': days,
      'targetReach': targetReach,
      'deliveredImpressions': 0,
      'paymentProvider': 'flutterwave',
      'createdAt': DateTime.now().toIso8601String(),
    };
    final row = await AppwriteService.createDocument(
      AppwriteService.postBoostsCollectionId,
      data,
    );
    return row;
  }

  static Future<void> markBoostRunning(
    String boostId,
    String postId, {
    String? paymentRef,
  }) async {
    final data = <String, dynamic>{
      'status': 'running',
      'startedAt': DateTime.now().toIso8601String(),
    };
    if (paymentRef != null && paymentRef.isNotEmpty) {
      data['paymentRef'] = paymentRef;
    }
    await AppwriteService.updateRow(
      AppwriteService.postBoostsCollectionId,
      boostId,
      data,
    );
    await AppwriteService.updateRow(AppwriteService.postsCollectionId, postId, {
      'isBoosted': true,
      'activeBoostId': boostId,
    });
  }

  static Future<void> markBoostFailed(String boostId) async {
    await AppwriteService.updateRow(
      AppwriteService.postBoostsCollectionId,
      boostId,
      {'status': 'failed'},
    );
  }

  static Future<models.RowList> fetchBoostsForUser(
    String userId, {
    String? status,
    int limit = 50,
  }) async {
    final queries = <String>[
      Query.equal('userId', userId),
      if (status != null) Query.equal('status', status),
      Query.limit(limit),
      Query.orderDesc('createdAt'),
    ];
    return AppwriteService.getDocuments(
      AppwriteService.postBoostsCollectionId,
      queries: queries,
    );
  }
}
