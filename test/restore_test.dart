import 'package:docview/features/reader/domain/restore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('clampRestoredPage', () {
    test('keeps valid 1-based pages', () {
      expect(clampRestoredPage(1, 10), 1);
      expect(clampRestoredPage(7, 10), 7);
      expect(clampRestoredPage(10, 10), 10);
    });

    test('rejects zero/negative pages', () {
      expect(clampRestoredPage(0, 10), 1);
      expect(clampRestoredPage(-4, 10), 1);
      expect(clampRestoredPage(null, 10), 1);
    });

    test('clamps stale pages to the current page count', () {
      expect(clampRestoredPage(99, 3), 3);
      expect(clampRestoredPage(99, 0), 99);
      expect(clampRestoredPage(99, null), 99);
    });
  });

  group('sanitizeProgress', () {
    test('accepts finite fractions in range', () {
      expect(sanitizeProgress(0), 0);
      expect(sanitizeProgress(0.42), 0.42);
      expect(sanitizeProgress(1), 1);
    });

    test('rejects non-finite junk', () {
      expect(sanitizeProgress(null), isNull);
      expect(sanitizeProgress(double.nan), isNull);
      expect(sanitizeProgress(double.infinity), isNull);
    });

    test('clamps out-of-range values', () {
      expect(sanitizeProgress(-0.5), 0);
      expect(sanitizeProgress(2.5), 1);
    });
  });

  group('sanitizeLocation', () {
    test('trims and keeps normal relocators', () {
      expect(sanitizeLocation(' epubcfi(/6/4!/2) '), 'epubcfi(/6/4!/2)');
      expect(sanitizeLocation(null), isNull);
      expect(sanitizeLocation('   '), isNull);
    });

    test('drops oversized relocators', () {
      expect(sanitizeLocation('x' * 5000), isNull);
    });
  });
}
