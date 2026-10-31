// Renders every signed-in page at phone and desktop sizes in light and dark
// mode using sample data, failing on any layout overflow or build exception.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:vigil/main.dart';
import 'package:vigil/providers/theme_provider.dart';

import 'preview/preview_data.dart';

const _routes = ['/dashboard', '/rosters', '/leave', '/staff', '/geofence', '/reports', '/settings', '/admin'];
const _sizes = {'phone': Size(375, 812), 'desktop': Size(1366, 860)};

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', publishableKey: 'test');
  });

  for (final role in ['admin', 'staff', 'system_admin']) {
    for (final theme in AppTheme.values) {
      for (final entry in _sizes.entries) {
        testWidgets('$role · ${theme.name} · ${entry.key}: all pages lay out cleanly', (tester) async {
          previewRole = role;
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          final container = ProviderContainer(overrides: previewOverrides);
          addTearDown(container.dispose);
          container.read(themeProvider.notifier).setTheme(theme);

          await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const VigilApp()));
          final router = container.read(goRouterProvider);

          for (final route in _routes) {
            router.go(route);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 600));
            await tester.pump(const Duration(milliseconds: 600));
            expect(tester.takeException(), isNull, reason: '$route threw while rendering');
          }
          // Tear down: close realtime channels (they retry against the fake
          // backend) and let animation timers finish.
          await tester.pumpWidget(const SizedBox());
          unawaited(Supabase.instance.client.removeAllChannels());
          await tester.pump(const Duration(seconds: 15));
        });
      }
    }
  }
}
