// Visual preview of the signed-in app with sample data and no backend.
// Not part of the production build. Run with:
//   flutter run -d chrome -t test/preview/main_preview.dart
// then open e.g. /#/dashboard, /#/leave, /#/rosters, /#/staff, /#/settings.
// Append ?role=staff to the URL to preview the staff experience.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:vigil/main.dart';

import 'preview_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  previewRole = Uri.base.queryParameters['role'] ?? 'owner';
  await Supabase.initialize(url: 'http://127.0.0.1:9', publishableKey: 'preview');
  runApp(ProviderScope(overrides: previewOverrides, child: const VigilApp()));
}
