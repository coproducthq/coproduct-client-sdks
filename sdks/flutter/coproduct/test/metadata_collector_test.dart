import 'package:coproduct/src/metadata_collector.dart';
import 'package:coproduct/src/rust/api.dart' as frb;
import 'package:flutter_test/flutter_test.dart';

void main() {
  MetadataProviders providers({
    Future<String?> Function()? timezone,
    Future<String?> Function()? osVersion,
  }) =>
      MetadataProviders(
        platform: () async => 'android',
        osVersion: osVersion ?? () async => '14',
        appVersion: () async => '2.3.1',
        appBuild: () async => '412',
        locale: () async => 'en-US',
        timezone: timezone ?? () async => 'America/New_York',
      );

  test('collects every available attribute', () async {
    final attrs = await collectStaticAttributes(providers(),
        perProviderTimeout: const Duration(seconds: 1));
    expect(attrs['platform'], const frb.FrbContextValue.string('android'));
    expect(attrs['os_version'], const frb.FrbContextValue.string('14'));
    expect(attrs['app_version'], const frb.FrbContextValue.string('2.3.1'));
    expect(attrs['app_build'], const frb.FrbContextValue.string('412'));
    expect(attrs['locale'], const frb.FrbContextValue.string('en-US'));
    expect(attrs['timezone'],
        const frb.FrbContextValue.string('America/New_York'));
  });

  test('a failing provider omits only its field, never throws', () async {
    final attrs = await collectStaticAttributes(
        providers(timezone: () async => throw StateError('no tz')),
        perProviderTimeout: const Duration(seconds: 1));
    expect(attrs.containsKey('timezone'), isFalse);
    expect(attrs['platform'], const frb.FrbContextValue.string('android'));
  });

  test('a hung provider times out and omits only its field', () async {
    final attrs = await collectStaticAttributes(
        providers(
            osVersion: () => Future.delayed(
                const Duration(seconds: 5), () => '14')),
        perProviderTimeout: const Duration(milliseconds: 20));
    expect(attrs.containsKey('os_version'), isFalse);
    expect(attrs['platform'], const frb.FrbContextValue.string('android'));
  });

  test('a null or empty value omits the field', () async {
    final ps = providers();
    final attrs = await collectStaticAttributes(
        MetadataProviders(
          platform: ps.platform,
          osVersion: () async => null,
          appVersion: () async => '',
          appBuild: ps.appBuild,
          locale: ps.locale,
          timezone: ps.timezone,
        ),
        perProviderTimeout: const Duration(seconds: 1));
    expect(attrs.containsKey('os_version'), isFalse);
    expect(attrs.containsKey('app_version'), isFalse);
  });

  test('reports each field duration and omission to the observer', () async {
    final ps = providers();
    final omissions = <String, bool>{};
    final counts = <String, int>{};
    await collectStaticAttributes(
        MetadataProviders(
          platform: ps.platform,
          osVersion: () async => throw StateError('no os'),
          appVersion: () async => '',
          appBuild: ps.appBuild,
          locale: ps.locale,
          timezone: ps.timezone,
        ),
        perProviderTimeout: const Duration(seconds: 1),
        observe: (field, elapsed, {required bool omitted}) {
          omissions[field] = omitted;
          counts[field] = (counts[field] ?? 0) + 1;
        });
    // Every field is reported exactly once, and the omitted flag reflects a
    // throw or an empty value as well as a clean collection
    expect(counts, {
      'platform': 1,
      'os_version': 1,
      'app_version': 1,
      'app_build': 1,
      'locale': 1,
      'timezone': 1,
    });
    expect(omissions['platform'], isFalse);
    expect(omissions['os_version'], isTrue); // threw
    expect(omissions['app_version'], isTrue); // empty
    expect(omissions['app_build'], isFalse);
  });

  test('a throwing observer never fails collection', () async {
    // A diagnostic sink that throws must not turn a best-effort collection into
    // a failed initialize, so collection still returns every available field
    final attrs = await collectStaticAttributes(providers(),
        perProviderTimeout: const Duration(seconds: 1),
        observe: (field, elapsed, {required bool omitted}) =>
            throw StateError('diagnostic sink is down'));
    expect(attrs['platform'], const frb.FrbContextValue.string('android'));
    expect(attrs['app_version'], const frb.FrbContextValue.string('2.3.1'));
    expect(attrs.length, 6);
  });
}
