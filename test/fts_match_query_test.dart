import 'package:docview/features/library/data/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ftsMatchQuery', () {
    test('empty string returns null', () {
      expect(LibraryRepository.ftsMatchQuery(''), isNull);
    });

    test('whitespace-only returns null', () {
      expect(LibraryRepository.ftsMatchQuery('   \n\t '), isNull);
    });

    test('punctuation-only returns null', () {
      expect(LibraryRepository.ftsMatchQuery('?!,.;'), isNull);
    });

    test('single word is quoted', () {
      expect(LibraryRepository.ftsMatchQuery('flutter'), equals('"flutter"'));
    });

    test('multiple words are individually quoted', () {
      expect(
        LibraryRepository.ftsMatchQuery('dart flutter'),
        equals('"dart" "flutter"'),
      );
    });

    test('caps at eight words', () {
      final nine = List.filled(9, 'word').join(' ');
      final result = LibraryRepository.ftsMatchQuery(nine)!;
      expect('" "'.allMatches(result).length, equals(7));
      expect(result.split(' '), hasLength(8));
    });

    test('punctuation between words is stripped', () {
      expect(
        LibraryRepository.ftsMatchQuery('hello, world!'),
        equals('"hello" "world"'),
      );
    });

    test('underscores and digits are kept', () {
      expect(
        LibraryRepository.ftsMatchQuery('snake_case 42'),
        equals('"snake_case" "42"'),
      );
    });
  });
}
