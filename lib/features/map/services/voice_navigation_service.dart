import 'package:flutter_tts/flutter_tts.dart';

class VoiceNavigationService {

  final FlutterTts tts =
      FlutterTts();

  Future<void> speak(
    String message,
  ) async {

    await tts.setLanguage('en-US');

    await tts.speak(message);
  }
}
