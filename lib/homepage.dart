import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

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
  bool isAnimatingDownload = false; // To track download animation state

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

  // Notification plugin instance
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Expiration Logic
  final DateTime expirationDate =
      DateTime(2024, 11, 01, 11, 59, 59); // Set to Oct 1, 2024, 11:59 pM

  bool get isExpired => DateTime.now().isAfter(expirationDate);

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  Future<void> _initializeBasicNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings,
        onDidReceiveNotificationResponse:
            (NotificationResponse response) async {
      final String? payload = response.payload;
      if (payload != null) {
        await OpenFile.open(payload); // Open the downloaded file
      }
    });
  }

  Future<void> _downloadTranscriptions() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Notifications for download progress',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
      icon:
          'mothersonlogo', // Replace with your actual icon name (without extension)
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    // Check for storage permissions
    if (await Permission.storage.request().isGranted) {
      // Show notification for download start
      await flutterLocalNotificationsPlugin.show(
        0,
        'Downloading Transcription',
        'Download in progress...',
        platformChannelSpecifics,
      );

      try {
        // Get the external storage directory
        final directory = await getExternalStorageDirectory();
        // Check if the directory is not null
        if (directory != null) {
          // Define the downloads directory
          final downloadsDirectory = Directory('${directory.path}/Download');

          // Ensure the downloads directory exists
          if (!await downloadsDirectory.exists()) {
            await downloadsDirectory.create(recursive: true);
          }

          // Specify the file path in the downloads directory
          final filePath =
              path.join(downloadsDirectory.path, 'transcription.txt');
          final file = File(filePath);

          // Combine all transcription texts into a formatted string
          final String content = transcriptions.map((t) {
            return 'Original: ${t.originalText}\nTranslated: ${t.translatedText}\n';
          }).join('\n');

          // Write the transcription to a file
          await file.writeAsString(content);

          // Show complete notification
          await flutterLocalNotificationsPlugin.show(
            0,
            'Download Complete',
            'Transcription saved at $filePath',
            platformChannelSpecifics,
            payload: filePath, // Pass the file path in the payload
          );
        } else {
          // Handle case where directory is null
          await flutterLocalNotificationsPlugin.show(
            0,
            'Download Failed',
            'Could not get download directory.',
            platformChannelSpecifics,
          );
        }
      } catch (e) {
        print("Error occurred: $e"); // Log the error for debugging
        await flutterLocalNotificationsPlugin.show(
          0,
          'Download Failed',
          'Failed to save transcription: $e',
          platformChannelSpecifics,
        );
      }
    } else {
      // Handle permission denial
      await flutterLocalNotificationsPlugin.show(
        0,
        'Permission Denied',
        'Storage permission is required to save transcription.',
        platformChannelSpecifics,
      );
    }
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
        // case 'German':
        //   translator = OnDeviceTranslator(
        //     sourceLanguage: TranslateLanguage.german,
        //     targetLanguage: getTargetLanguageEnum(),
        //   );
        //   break;
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
      // case 'German':
      //   return TranslateLanguage.german;
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
      // case 'German':
      //   return TranslateLanguage.german;
      default:
        return TranslateLanguage.english;
    }
  }

  Future<void> _speak(String text, String language) async {
    if (language == 'French') {
      await _tts.setLanguage('fr-FR');
    } else if (language == 'Hindi') {
      await _tts.setLanguage('hi-IN');
    } else if (language == 'German') {
      await _tts.setLanguage('de-DE');
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

                  // Conditionally show the download button if transcriptions is not empty
                  if (transcriptions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: ElevatedButton(
                        onPressed: () async {
                          setState(() {
                            isAnimatingDownload = true; // Start the animation
                          });

                          // Wait for 1 second before starting the download
                          await Future.delayed(const Duration(seconds: 2));

                          setState(() {
                            isAnimatingDownload = false; // Stop the animation
                          });

                          _downloadTranscriptions(); // Download function
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(6.0),
                          backgroundColor:
                              Colors.redAccent, // Color for the button
                          shape: const CircleBorder(), // Circular button shape
                        ),
                        child: isAnimatingDownload
                            ? LoadingAnimationWidget.hexagonDots(
                                color: Colors.white,
                                size: 30) // Animation during download
                            : const Icon(
                                Icons.file_download,
                                size: 30, // Same size as previous
                                color: Colors.white, // White icon for contrast
                              ),
                      ),
                    ),

                  // Right Mic
                  GestureDetector(
                    onTap: () async {
                      if (!isRecordingRight) {
                        _toggleRecordingRight();
                        setState(() {
                          isWaitingRight = true;
                          isAnimatingDotsRight = false;
                        });
                        await Future.delayed(const Duration(seconds: 1));
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
