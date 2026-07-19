import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../models/models.dart';

final plantsProvider =
    AsyncNotifierProvider<PlantsNotifier, List<Plant>>(PlantsNotifier.new);

class PlantsNotifier extends AsyncNotifier<List<Plant>> {
  ApiClient get _api => ref.read(apiProvider);

  @override
  Future<List<Plant>> build() => _fetch();

  Future<List<Plant>> _fetch() async {
    final res = await _api.dio.get('/api/plants');
    final plants = (res.data['plants'] as List)
        .map((e) => Plant.fromJson(e as Map<String, dynamic>))
        .toList();
    return plants;
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(_fetch);
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
    await reload();
    return Plant.fromJson(res.data['plant'] as Map<String, dynamic>);
  }

  Future<void> water(String plantId) async {
    await _api.dio.post('/api/plants/$plantId/water');
    await reload();
  }

  Future<int> waterAll() async {
    final res = await _api.dio.post('/api/plants/water-all');
    await reload();
    return (res.data['watered'] ?? 0) as int;
  }

  Future<void> deletePlant(String plantId) async {
    await _api.dio.delete('/api/plants/$plantId');
    await reload();
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
    await reload();
    return res.data as Map<String, dynamic>;
  }
}

class PlantDetails {
  PlantDetails({required this.plant, required this.journal, required this.reminders});

  final Plant plant;
  final List<JournalEntry> journal;
  final List<Reminder> reminders;
}

final plantDetailsProvider = FutureProvider.autoDispose
    .family<PlantDetails, String>((ref, plantId) async {
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
  );
});

final scanQuotaProvider = FutureProvider.autoDispose<ScanQuota>((ref) async {
  final api = ref.watch(apiProvider);
  final res = await api.dio.get('/api/scan/quota');
  return ScanQuota.fromJson(res.data as Map<String, dynamic>);
});
