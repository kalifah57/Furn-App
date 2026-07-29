import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/shared/models/models.dart';

void main() {
  group('FurnishingProject JSON', () {
    // مطابق لهيكل json_schema.md.
    final sample = <String, dynamic>{
      'project_id': 'p1',
      'locale': 'ar-SA',
      'room': {
        'name': 'غرفتي',
        'width_m': 4,
        'length_m': 6,
        'height_m': 3,
        'room_type': 'bedroom',
      },
      'budget': {'currency': 'SAR', 'max_total': 1800, 'flexible': false},
      'style': {
        'preferred': ['modern', 'minimal'],
        'colors': ['gray'],
        'notes': '',
      },
      'items': {
        'essential': [
          {'type': 'bed', 'constraints': ['small', 'double'], 'quantity': 1}
        ],
        'optional': [
          {'type': 'rug', 'constraints': ['if_budget_allows'], 'quantity': 1}
        ],
      },
      'analysis': {
        'summary': 'ملخص',
        'missing_information': [],
        'warnings': [],
        'confidence_score': 0.8,
      },
      'recommendations': {'individual_items': [], 'bundles': []},
      'next_actions': {'ask_for_images': false, 'follow_up_questions': []},
    };

    test('fromJson parses all sections', () {
      final p = FurnishingProject.fromJson(sample);
      expect(p.projectId, 'p1');
      expect(p.room.roomType, RoomType.bedroom);
      expect(p.room.areaM2, 24);
      expect(p.budget.maxTotal, 1800);
      expect(p.style.preferred, ['modern', 'minimal']);
      expect(p.items.essential.single.type, 'bed');
      expect(p.items.optional.single.constraints, ['if_budget_allows']);
      expect(p.analysis.confidenceScore, 0.8);
    });

    test('round-trip preserves core fields', () {
      final p = FurnishingProject.fromJson(sample);
      final again = FurnishingProject.fromJson(p.toJson());
      expect(again, p);
    });

    test('unknown enum values fall back safely', () {
      final p = FurnishingProject.fromJson({
        'project_id': 'x',
        'room': {'room_type': 'garage'},
      });
      expect(p.room.roomType, RoomType.other);
    });
  });
}
