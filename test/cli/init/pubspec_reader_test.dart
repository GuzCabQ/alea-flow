import 'package:alea_flow/src/cli/init/pubspec_reader.dart';
import 'package:test/test.dart';

void main() {
  group('PubspecReader.parse', () {
    test('extracts package name and detects Flutter project', () {
      const yaml = '''
name: my_app
version: 0.1.0
environment:
  sdk: ^3.0.0
  flutter: ">=3.0.0"
dependencies:
  flutter:
    sdk: flutter
''';
      final data = const PubspecReader().parse(yaml);
      expect(data.packageName, 'my_app');
      expect(data.isFlutterProject, isTrue);
    });

    test('detects pure Dart project (no flutter dep, no flutter env)', () {
      const yaml = '''
name: pure_dart_pkg
environment:
  sdk: ^3.0.0
dependencies:
  args: ^2.0.0
''';
      final data = const PubspecReader().parse(yaml);
      expect(data.packageName, 'pure_dart_pkg');
      expect(data.isFlutterProject, isFalse);
    });

    test('infers riverpod_manual from flutter_riverpod', () {
      const yaml = '''
name: app
dependencies:
  flutter_riverpod: ^2.0.0
''';
      final data = const PubspecReader().parse(yaml);
      expect(data.stateManagementStyle, 'riverpod_manual');
      expect(data.stateManagementOrigin, 'flutter_riverpod');
    });

    test('infers bloc from flutter_bloc', () {
      const yaml = '''
name: app
dependencies:
  flutter_bloc: ^8.0.0
''';
      final data = const PubspecReader().parse(yaml);
      expect(data.stateManagementStyle, 'bloc');
      expect(data.stateManagementOrigin, 'flutter_bloc');
    });

    test('infers provider from provider', () {
      const yaml = '''
name: app
dependencies:
  provider: ^6.0.0
''';
      final data = const PubspecReader().parse(yaml);
      expect(data.stateManagementStyle, 'provider');
    });

    test('infers getx from get', () {
      const yaml = '''
name: app
dependencies:
  get: ^4.0.0
''';
      final data = const PubspecReader().parse(yaml);
      expect(data.stateManagementStyle, 'getx');
      expect(data.stateManagementOrigin, 'get');
    });

    test('returns null state management when no known dep is present', () {
      const yaml = '''
name: app
dependencies:
  args: ^2.0.0
''';
      final data = const PubspecReader().parse(yaml);
      expect(data.stateManagementStyle, isNull);
      expect(data.stateManagementOrigin, isNull);
    });

    test('prefers flutter_riverpod over plain riverpod when both present', () {
      const yaml = '''
name: app
dependencies:
  flutter_riverpod: ^2.0.0
  riverpod: ^2.0.0
''';
      final data = const PubspecReader().parse(yaml);
      expect(data.stateManagementOrigin, 'flutter_riverpod');
    });

    test('infers go_router from dependencies', () {
      const yaml = '''
name: app
dependencies:
  go_router: ^12.0.0
''';
      final data = const PubspecReader().parse(yaml);
      expect(data.routingPackage, 'go_router');
      expect(data.routingOrigin, 'go_router');
    });

    test('infers auto_route from dependencies', () {
      const yaml = '''
name: app
dependencies:
  auto_route: ^7.0.0
''';
      final data = const PubspecReader().parse(yaml);
      expect(data.routingPackage, 'auto_route');
    });

    test('returns null routing when no known router dep present', () {
      const yaml = '''
name: app
dependencies:
  args: ^2.0.0
''';
      final data = const PubspecReader().parse(yaml);
      expect(data.routingPackage, isNull);
    });

    test('throws PubspecReaderException when name is missing', () {
      const yaml = '''
version: 0.1.0
dependencies:
  args: ^2.0.0
''';
      expect(
        () => const PubspecReader().parse(yaml),
        throwsA(isA<PubspecReaderException>()),
      );
    });

    test('throws PubspecReaderException when name is empty', () {
      const yaml = '''
name: ""
dependencies:
  args: ^2.0.0
''';
      expect(
        () => const PubspecReader().parse(yaml),
        throwsA(isA<PubspecReaderException>()),
      );
    });

    test('throws PubspecReaderException on malformed YAML', () {
      const yaml = 'this is: not: a valid yaml: { mapping';
      expect(
        () => const PubspecReader().parse(yaml),
        throwsA(isA<PubspecReaderException>()),
      );
    });

    test('throws PubspecReaderException when root is not a map', () {
      const yaml = '- just\n- a\n- list';
      expect(
        () => const PubspecReader().parse(yaml),
        throwsA(isA<PubspecReaderException>()),
      );
    });
  });

  group('PubspecReader.read', () {
    test('throws when file does not exist', () {
      expect(
        () => const PubspecReader().read('/nonexistent/pubspec.yaml'),
        throwsA(isA<PubspecReaderException>()),
      );
    });
  });
}
