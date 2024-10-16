import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslatorService {
  OnDeviceTranslator? _translator;

  // Method to translate the text
  Future<String> translateText(
      String text, String fromLanguage, String toLanguage) async {
    try {
      // Get language models for source and target languages
      TranslateLanguage sourceLang = _getLanguageModel(fromLanguage);
      TranslateLanguage targetLang = _getLanguageModel(toLanguage);

      // Create the translator instance with specified source and target languages
      _translator = OnDeviceTranslator(
        sourceLanguage: sourceLang,
        targetLanguage: targetLang,
      );

      // Translate the text
      String translatedText = await _translator!.translateText(text);

      // Return the translated text
      return translatedText;
    } catch (e) {
      // Handle exceptions and return error message
      return 'Error during translation: $e';
    }
  }

  // Helper function to convert language string to TranslateLanguage model
  TranslateLanguage _getLanguageModel(String language) {
    switch (language.toLowerCase()) {
      case 'english':
        return TranslateLanguage.english;
      case 'spanish':
        return TranslateLanguage.spanish;
      case 'french':
        return TranslateLanguage.french;
      case 'german':
        return TranslateLanguage.german;
      case 'hindi':
        return TranslateLanguage.hindi;
      // Add more languages here as needed
      default:
        return TranslateLanguage.english;
    }
  }
}
