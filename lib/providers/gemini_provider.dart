import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// Provides an instance of the Gemini API client using the google_generative_ai package.
/// The model returned here is 'gemini-1.5-pro' by default, but you can configure it.
final geminiProvider = Provider<GenerativeModel?>((ref) {
  final apiKey = dotenv.env['GEMINI_API_KEY'];
  
  if (apiKey == null || apiKey.isEmpty || apiKey == 'your_api_key_here') {
    return null;
  }
  
  return GenerativeModel(
    model: 'gemini-2.5-pro',
    apiKey: apiKey,
  );
});
