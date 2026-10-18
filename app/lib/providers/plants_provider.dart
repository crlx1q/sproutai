import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../models/models.dart';
import '../models/weekly_history.dart';
import '../services/push_service.dart';
import 'auth_provider.dart';

final plantsProvider = AsyncNotifierProvider<PlantsNotifier, List<Plant>>(
  PlantsNotifier.new,
);

class PlantsNotifier extends AsyncNotifier<List<Plant>> {
  ApiClient get _api => ref.read(apiProvider);

  @override
  Future<List<Plant>> build() {
    final userId = ref.watch(
      authProvider.select((auth) => auth is AuthLoggedIn ? auth.user.id : null),
    );
    return userId == null ? Future.value([]) : _fetch();
  }

  String? get _userId {
    final auth = ref.read(authProvider);
    return auth is AuthLoggedIn ? auth.user.id : null;
  }

  Future<List<Plant>> _fetch() async {
    final userId = _userId;
    if (userId == null) return [];
    final res = await _api.dio.get('/api/plants');
    final plants = (res.data['plants'] as List)
        .map((e) => Plant.fromJson(e as Map<String, dynamic>))
        .toList();
    if (!ref.mounted || _userId != userId) return [];
    await PushService.instance.syncReminders(plants);
    return plants;
  }

  Future<void> reload() async {
    final userId = _userId;
    try {
      final plants = await _fetch();
      if (ref.mounted && userId == _userId) state = AsyncData(plants);
    } catch (error, stack) {
      if (ref.mounted && userId == _userId) state = AsyncError(error, stack);
      rethrow;
    }
  }

  Future<void> _reloadAfterMutation() async {
    try {
      await reload();
    } catch (_) {
      // The write succeeded. A failed refresh must not invite a duplicate write.
    }
  }

  Future<Plant> addPlant({
    required String name,
    String? species,
    String location = 'indoor',
    MultipartFile? photo,
    Map<String, dynamic>? care,
    String origin = 'existing',
    String? stage,
    DateTime? plantedAt,
    String? growthGoal,
  }) async {
    final form = FormData.fromMap({
      'name': name,
      if (species != null) 'species': species,
      'location': location,
      'origin': origin,
      if (stage != null) 'stage': stage,
      if (plantedAt != null) 'plantedAt': plantedAt.toIso8601String(),
      if (growthGoal != null && growthGoal.isNotEmpty) 'growthGoal': growthGoal,
      if (photo != null) 'photo': photo,
      if (care != null) 'care': jsonEncode(care),
    });
    final res = await _api.dio.post('/api/plants', data: form);
    await _reloadAfterMutation();
    return Plant.fromJson(res.data['plant'] as Map<String, dynamic>);
  }

  Future<void> water(String plantId) async {
    await _api.dio.post('/api/plants/$plantId/water');
    await _reloadAfterMutation();
    ref.invalidate(plantDetailsProvider(plantId));
  }

  Future<void> fertilize(String plantId) async {
    await _api.dio.post('/api/plants/$plantId/fertilize');
    await _reloadAfterMutation();
    ref.invalidate(plantDetailsProvider(plantId));
  }

  Future<void> snooze(String plantId, String type, {int days = 1}) async {
    await _api.dio.post(
      '/api/plants/$plantId/care/snooze',
      data: {'type': type, 'days': days},
    );
    await _reloadAfterMutation();
    ref.invalidate(plantDetailsProvider(plantId));
  }

  Future<void> updatePlant(String plantId, Map<String, dynamic> data) async {
    await _api.dio.patch('/api/plants/$plantId', data: data);
    await _reloadAfterMutation();
    ref.invalidate(plantDetailsProvider(plantId));
  }

  Future<void> addJournal(
    String plantId, {
    String note = '',
    MultipartFile? photo,
    bool analyze = true,
    String kind = 'progress',
  }) async {
    await _api.dio.post(
      '/api/plants/$plantId/journal',
      data: FormData.fromMap({
        'note': note,
        'kind': kind,
        'analyze': analyze.toString(),
        if (photo != null) 'photo': photo,
      }),
    );
    await _reloadAfterMutation();
    ref.invalidate(plantDetailsProvider(plantId));
    ref.invalidate(scanQuotaProvider);
  }

  Future<int> waterAll() async {
    final res = await _api.dio.post('/api/plants/water-all');
    await _reloadAfterMutation();
    return (res.data['watered'] ?? 0) as int;
  }

  Future<void> deletePlant(String plantId) async {
    await _api.dio.delete('/api/plants/$plantId');
    await _reloadAfterMutation();
  }

  /// Плановый ИИ-чекап: отправляем свежее фото, ИИ обновляет состояние
  /// растения и добавляет запись в историю. Возвращает тело ответа.
  Future<Map<String, dynamic>> checkup(
    String plantId,
    MultipartFile photo, {
    String? note,
  }) async {
    final form = FormData.fromMap({
      'photo': photo,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    final res = await _api.dio.post('/api/plants/$plantId/checkup', data: form);
    await _reloadAfterMutation();
    ref.invalidate(plantDetailsProvider(plantId));
    ref.invalidate(scanQuotaProvider);
    return res.data as Map<String, dynamic>;
  }
}

class PlantDetails {
  PlantDetails({
    required this.plant,
    required this.journal,
    required this.reminders,
    this.weeklyHistory = const [],
  });

  final Plant plant;
  final List<JournalEntry> journal;
  final List<Reminder> reminders;
  final List<PlantWeek> weeklyHistory;
}

final plantDetailsProvider = FutureProvider.autoDispose
    .family<PlantDetails, String>((ref, plantId) async {
      ref.watch(
        authProvider.select(
          (auth) => auth is AuthLoggedIn ? auth.user.id : null,
        ),
      );
      final api = ref.watch(apiProvider);
      final res = await api.dio.get('/api/plants/$plantId');
      return PlantDetails(
        plant: Plant.fromJson(res.data['plant'] as Map<String, dynamic>),
        journal: (res.data['journal'] as List)
            .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        reminders: (res.data['reminders'] as List)
            .map((e) => Reminder.fromJson(e as Map<String, dynamic>))
            .toList(),
        weeklyHistory: ((res.data['weeklyHistory'] ?? []) as List)
            .map((e) => PlantWeek.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    });

final scanQuotaProvider = FutureProvider.autoDispose<ScanQuota>((ref) async {
  ref.watch(
    authProvider.select((auth) => auth is AuthLoggedIn ? auth.user.id : null),
  );
  final api = ref.watch(apiProvider);
  final res = await api.dio.get('/api/scan/quota');
  return ScanQuota.fromJson(res.data as Map<String, dynamic>);
});
