import 'package:flutter_test/flutter_test.dart';
import 'package:sprout_ai/models/models.dart';

void main() {
  test('Plant парсится из JSON', () {
    final plant = Plant.fromJson({
      '_id': 'abc',
      'name': 'Монстера',
      'species': 'Monstera deliciosa',
      'healthScore': 88,
      'care': {'wateringIntervalDays': 5},
      'needsWater': true,
    });
    expect(plant.name, 'Монстера');
    expect(plant.care.wateringIntervalDays, 5);
    expect(plant.needsWater, true);
  });
}
