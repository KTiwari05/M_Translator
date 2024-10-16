import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(const TranslatorApp());
}

class TranslatorApp extends StatelessWidget {
  const TranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: TranslatorScreen(),
    );
  }
}

class TranslatorScreen extends StatefulWidget {
  const TranslatorScreen({super.key});

  @override
  _TranslatorScreenState createState() => _TranslatorScreenState();
}

class _TranslatorScreenState extends State<TranslatorScreen> {
  bool isRecordingLeft = false;
  bool isRecordingRight = false;
  bool isAnimatingCircular = false; // To track circular animation
  bool isAnimatingDots = false; // To track staggered dots animation
  bool isAnimatingCircularLeft =
      false; // To track circular animation for left mic
  bool isAnimatingDotsLeft =
      false; // To track staggered dots animation for left mic
  bool isAnimatingCircularRight =
      false; // To track circular animation for right mic
  bool isAnimatingDotsRight =
      false; // To track staggered dots animation for right mic
  bool isWaitingLeft = false; // To track waiting state for left mic
  bool isWaitingRight = false; // To track waiting state for right mic

  String selectedSourceLanguage = 'English';
  String selectedTargetLanguage = 'French';

  List<String> languages = ['English', 'French', 'Hindi'];
  List<Transcription> transcriptions = [];
  final ScrollController _scrollController = ScrollController();

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  SpeechService? _speechService;
  Recognizer? _recognizer;

  String accumulatedTextLeft = "";
  String accumulatedTextRight = "";
  final FlutterTts _tts = FlutterTts();
  OnDeviceTranslator? translator;

  // Expiration Logic
  final DateTime expirationDate =
      DateTime(2124, 10, 9, 23, 59, 59); // Set to Oct 9, 2024, 11:59 pM

  bool get isExpired => DateTime.now().isAfter(expirationDate);

  @override
  void initState() {
    super.initState();
  }

  Future<void> _showEditDialog(Transcription transcription, bool isLeft) async {
    final TextEditingController controller = TextEditingController();
    controller.text = transcription.originalText;

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Transcription'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: "Edit the original text",
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () async {
                // Save the edited text
                setState(() {
                  transcription.originalText = controller.text;
                });

                // Translate the edited text
                final newTranslation = await _translateText(
                  transcription.originalText,
                  isLeft,
                );

                setState(() {
                  transcription.translatedText = newTranslation;

                  // Update the translated language based on direction
                  if (isLeft) {
                    transcription.translatedLanguage = selectedTargetLanguage;
                  } else {
                    transcription.translatedLanguage = selectedSourceLanguage;
                  }
                });

                // Speak the new translation in the correct language
                await _speak(newTranslation, transcription.translatedLanguage);

                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _toggleRecordingLeft() async {
    setState(() {
      isRecordingLeft = !isRecordingLeft;
      if (isRecordingLeft) {
        isRecordingRight = false;
        accumulatedTextLeft = "";
        _startRecognition(selectedSourceLanguage, true);
      } else {
        _stopRecognition();
      }
    });
  }

  void _toggleRecordingRight() async {
    setState(() {
      isRecordingRight = !isRecordingRight;
      if (isRecordingRight) {
        isRecordingLeft = false;
        accumulatedTextRight = "";
        _startRecognition(selectedTargetLanguage, false);
      } else {
        _stopRecognition();
      }
    });
  }

  Future<void> _startRecognition(String language, bool isLeft) async {
    try {
      _recognizer = await _vosk.createRecognizer(
          model: await _loadModel(language), sampleRate: 16000);
      if (_speechService == null) {
        _speechService = await _vosk.initSpeechService(_recognizer!);
        _speechService!.start();

        _speechService!.onResult().listen((event) {
          Map<String, dynamic> jsonResponse = json.decode(event);
          String convertedText = jsonResponse['text'].toString().trim();
          if (convertedText.isNotEmpty) {
            setState(() {
              if (isLeft) {
                accumulatedTextLeft += " $convertedText";
              } else {
                accumulatedTextRight += " $convertedText";
              }
            });
          }
        });
      }
    } catch (e) {
      setState(() {
        transcriptions.add(Transcription("Error: ${e.toString()}",
            translatedText: "",
            originalLanguage: selectedSourceLanguage,
            translatedLanguage: selectedTargetLanguage,
            isLeft: true));
      });
    }
  }

  Future<void> _stopRecognition() async {
    if (_speechService != null) {
      await _speechService!.stop();
      await _speechService!.dispose();
      _speechService = null;

      // Handle left mic (left-to-right translation)
      if (accumulatedTextLeft.isNotEmpty) {
        final translatedText =
            await _translateText(accumulatedTextLeft.trim(), true);
        setState(() {
          transcriptions.add(Transcription(
            accumulatedTextLeft.trim(),
            translatedText: translatedText,
            originalLanguage: selectedSourceLanguage,
            translatedLanguage: selectedTargetLanguage,
            isLeft: true,
          ));
          accumulatedTextLeft = "";
          _scrollToBottom();
        });

        await _speak(translatedText, selectedTargetLanguage);
      }

      // Handle right mic (right-to-left translation)
      if (accumulatedTextRight.isNotEmpty) {
        final translatedText =
            await _translateText(accumulatedTextRight.trim(), false);
        setState(() {
          transcriptions.add(Transcription(
            accumulatedTextRight.trim(),
            translatedText: translatedText,
            originalLanguage: selectedTargetLanguage,
            translatedLanguage: selectedSourceLanguage,
            isLeft: false,
          ));
          accumulatedTextRight = "";
          _scrollToBottom();
        });

        await _speak(translatedText, selectedSourceLanguage);
      }
    }

    if (_recognizer != null) {
      await _recognizer!.dispose();
      _recognizer = null;
    }
  }

  Future<String> _translateText(String text, bool isLeft) async {
    if (isLeft) {
      switch (selectedSourceLanguage) {
        case 'English':
          translator = OnDeviceTranslator(
            sourceLanguage: TranslateLanguage.english,
            targetLanguage: getTargetLanguageEnum(),
          );
          break;
        case 'French':
          translator = OnDeviceTranslator(
            sourceLanguage: TranslateLanguage.french,
            targetLanguage: getTargetLanguageEnum(),
          );
          break;
        case 'Hindi':
          translator = OnDeviceTranslator(
            sourceLanguage: TranslateLanguage.hindi,
            targetLanguage: getTargetLanguageEnum(),
          );
          break;
        default:
          translator = OnDeviceTranslator(
            sourceLanguage: TranslateLanguage.english,
            targetLanguage: getTargetLanguageEnum(),
          );
      }
    } else {
      translator = OnDeviceTranslator(
        sourceLanguage: getTargetLanguageEnum(),
        targetLanguage: getLeftSelectedLanguageEnum(),
      );
    }

    final translation = await translator!.translateText(text);
    return translation;
  }

  TranslateLanguage getLeftSelectedLanguageEnum() {
    switch (selectedSourceLanguage) {
      case 'English':
        return TranslateLanguage.english;
      case 'French':
        return TranslateLanguage.french;
      case 'Hindi':
        return TranslateLanguage.hindi;
      default:
        return TranslateLanguage.english;
    }
  }

  TranslateLanguage getTargetLanguageEnum() {
    switch (selectedTargetLanguage) {
      case 'English':
        return TranslateLanguage.english;
      case 'French':
        return TranslateLanguage.french;
      case 'Hindi':
        return TranslateLanguage.hindi;
      default:
        return TranslateLanguage.english;
    }
  }

  Future<void> _speak(String text, String language) async {
    if (language == 'French') {
      await _tts.setLanguage('fr-FR');
    } else if (language == 'Hindi') {
      await _tts.setLanguage('hi-IN');
    } else {
      await _tts.setLanguage('en-US');
    }

    await _tts.setPitch(1.0);
    await _tts.speak(text);
  }

  Future<Model> _loadModel(String language) async {
    String modelPath;
    if (language == 'English') {
      modelPath = 'assets/models/vosk-model-small-en-in-0.4.zip';
    } else if (language == 'French') {
      modelPath = 'assets/models/vosk-model-small-fr-0.22.zip';
    } else if (language == 'Hindi') {
      modelPath = 'assets/models/vosk-model-small-hi-0.22.zip';
    } else {
      modelPath = 'assets/models/vosk-model-small-en-in-0.4.zip';
    }

    final loadedModelPath = await ModelLoader().loadFromAssets(modelPath);
    return await _vosk.createModel(loadedModelPath);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    // If the app is expired, show a message
    if (isExpired) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.redAccent,
          title: const Text('App Expired'),
        ),
        body: const Center(
          child: Text(
            'This app has expired. Please contact the developer.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, color: Colors.red),
          ),
        ),
      );
    }

    // If the app is not expired, show the main content
    return Scaffold(
      // appBar: CustomAppBar(
      //   onToggle: () {},
      // ), // Use your custom AppBar
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        color: const Color(0xFFE4E3E0),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: transcriptions.length,
                itemBuilder: (context, index) {
                  final transcription = transcriptions[index];
                  return _buildChatBubble(transcription);
                },
              ),
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildLanguageButton(selectedSourceLanguage, true),
                  IconButton(
                    icon: const Icon(Icons.swap_horiz, size: 45),
                    onPressed: _swapLanguages,
                  ),
                  _buildLanguageButton(selectedTargetLanguage, false),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left Mic
                  GestureDetector(
                    onTap: () async {
                      if (!isRecordingLeft) {
                        _toggleRecordingLeft();

                        setState(() {
                          isWaitingLeft = true;
                          isAnimatingDotsLeft = false;
                        });

                        await Future.delayed(
                            const Duration(milliseconds: 1000));

                        await Future.delayed(const Duration(milliseconds: 450));

                        setState(() {
                          isWaitingLeft = false;
                          isAnimatingDotsLeft = true;
                        });
                      } else {
                        _toggleRecordingLeft();

                        setState(() {
                          isWaitingLeft = false;
                          isAnimatingDotsLeft = false;
                        });
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor:
                            isRecordingRight ? Colors.grey : Colors.redAccent,
                        child: isRecordingLeft
                            ? (isWaitingLeft
                                ? LoadingAnimationWidget.inkDrop(
                                    color: Colors.white, size: 35)
                                : LoadingAnimationWidget.staggeredDotsWave(
                                    color: Colors.white, size: 35))
                            : const Icon(Icons.mic,
                                color: Colors.white, size: 35),
                      ),
                    ),
                  ),

                  // Right Mic
                  GestureDetector(
                    onTap: () async {
                      if (!isRecordingRight) {
                        _toggleRecordingRight();
                        // Start the discrete circular animation
                        setState(() {
                          isWaitingRight = true;
                          isAnimatingDotsRight = false;
                        });

                        // Wait for 1 second for the discrete animation
                        await Future.delayed(const Duration(seconds: 1));

                        // Wait for an additional 2 seconds before starting
                        await Future.delayed(const Duration(milliseconds: 450));

                        setState(() {
                          isWaitingRight = false;
                          isAnimatingDotsRight = true;
                        });
                      } else {
                        _toggleRecordingRight();

                        setState(() {
                          isWaitingRight = false;
                          isAnimatingDotsRight = false;
                        });
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor:
                            isRecordingLeft ? Colors.grey : Colors.redAccent,
                        child: isRecordingRight
                            ? (isWaitingRight
                                ? LoadingAnimationWidget.inkDrop(
                                    color: Colors.white, size: 35)
                                : LoadingAnimationWidget.staggeredDotsWave(
                                    color: Colors.white, size: 35))
                            : const Icon(Icons.mic,
                                color: Colors.white, size: 35),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _swapLanguages() {
    setState(() {
      String temp = selectedSourceLanguage;
      selectedSourceLanguage = selectedTargetLanguage;
      selectedTargetLanguage = temp;
    });
  }

  Widget _buildChatBubble(Transcription transcription) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 255, 255, 255),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Original Language: ${transcription.originalText}',
                      style: const TextStyle(
                        color: Color.fromARGB(255, 85, 84, 84),
                        fontWeight: FontWeight.w500,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit,
                              size: 17, color: Colors.grey),
                          onPressed: () => _showEditDialog(
                              transcription, transcription.isLeft),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy,
                              size: 16, color: Colors.grey),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: transcription.originalText),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Original text copied to clipboard!'),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.volume_up,
                              size: 18, color: Colors.blue),
                          onPressed: () => _speak(
                            transcription.originalText,
                            transcription.originalLanguage,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Translated Language: ${transcription.translatedText}',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.copy,
                              size: 16, color: Colors.grey),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: transcription.translatedText),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Translated text copied to clipboard!'),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.volume_up,
                              size: 18, color: Colors.blue),
                          onPressed: () => _speak(
                            transcription.translatedText,
                            transcription.translatedLanguage,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.delete,
                              size: 19, color: Colors.red),
                          onPressed: () => _confirmDelete(transcription),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

// Function to show confirmation dialog for deletion
  void _confirmDelete(Transcription transcription) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text('Are you sure you want to delete this chat?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Delete'),
              onPressed: () {
                _deleteTranscription(transcription);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

// Method to delete a transcription
  void _deleteTranscription(Transcription transcription) {
    setState(() {
      transcriptions.remove(transcription);
    });
  }

  Widget _buildLanguageButton(String language, bool isLeft) {
    return GestureDetector(
      onTap: () => _showLanguageSelection(context, isLeft),
      child: Container(
        width: 120,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          language,
          style: const TextStyle(
            fontSize: 18,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _showLanguageSelection(BuildContext context, bool isLeft) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: languages.map((language) {
              return ListTile(
                title: Text(language),
                onTap: () {
                  setState(() {
                    if (isLeft) {
                      selectedSourceLanguage = language;
                    } else {
                      selectedTargetLanguage = language;
                    }
                  });
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class Transcription {
  String originalText;
  String translatedText;
  String originalLanguage;
  String translatedLanguage;
  bool isLeft;

  Transcription(this.originalText,
      {this.translatedText = "",
      this.originalLanguage = "",
      this.translatedLanguage = "",
      required this.isLeft});
}
