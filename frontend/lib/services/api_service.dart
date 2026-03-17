import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ApiService {
  final String baseUrl;
  int? currentSessionId;

  ApiService({required this.baseUrl});

  // --- Session Management ---
  Future<int?> startSession(int userId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/session/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        currentSessionId = data['session_id'];
        debugPrint('[ApiService] Session started: $currentSessionId');
        return currentSessionId;
      }
    } catch (e) {
      debugPrint('[ApiService] Error starting session: $e');
    }
    return null;
  }

  Future<bool> endSession({
    required int exerciseCount,
    required double avgAccuracy,
    required double avgTremorScore,
  }) async {
    if (currentSessionId == null) return false;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/session/end'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': currentSessionId,
          'exercise_count': exerciseCount,
          'avg_accuracy': avgAccuracy,
          'avg_tremor_score': avgTremorScore,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('[ApiService] Session ended');
        currentSessionId = null;
        return true;
      }
    } catch (e) {
      debugPrint('[ApiService] Error ending session: $e');
    }
    return false;
  }

  // --- AI Data Endpoints ---
  Future<Map<String, dynamic>?> sendPoseData({
    required int userId,
    required List<Map<String, dynamic>> landmarks,
    String exercise = 'arm_raise',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/pose-data/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'session_id': currentSessionId,
          'landmarks': landmarks,
          'exercise': exercise,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('[ApiService] Error sending pose data: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getProgress(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/progress/$userId'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('[ApiService] Error fetching progress: $e');
    }
    return null;
  }
}
