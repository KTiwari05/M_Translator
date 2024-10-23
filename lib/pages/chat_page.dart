import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'translator_service.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class ChatPage extends StatefulWidget {
  final String roomId;
  final String name;
  final String language;
  final IO.Socket socket;

  const ChatPage(
      {super.key,
      required this.roomId,
      required this.name,
      required this.language,
      required this.socket});

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<Map<String, String>> messages = [];
  final ScrollController _scrollController = ScrollController();
  final TranslatorService _translatorService = TranslatorService();
  final FlutterTts _tts = FlutterTts();

  bool _isRecording = false;
  bool isWaiting = false;
  bool isAnimatingDots = false;
  String accumulatedText = '';
  Recognizer? _recognizer;
  SpeechService? _speechService;
  final _vosk = VoskFlutterPlugin.instance();
  final _modelLoader = ModelLoader();

  // State variable to track multiple users currently speaking
  Set<String> currentlySpeakingUsers = {};

  // State variable to track the active speaker
  String? activeSpeaker;

  @override
  void initState() {
    super.initState();

    widget.socket.onConnect((_) {
      print("Connected to the server");
    });

    widget.socket.on('receive-message', (data) async {
      String senderLanguage = data['senderLanguage'];
      String translatedMessage = data['message'];

      // Translate if sender's language is different from receiver's
      if (senderLanguage != widget.language) {
        translatedMessage = await _translatorService.translateText(
            translatedMessage, senderLanguage, widget.language);
      }

      setState(() {
        messages.add({
          'sender': data['sender'],
          'message': translatedMessage,
          'senderLanguage': senderLanguage
        });
      });

      // Play TTS for received messages only
      if (data['sender'] != widget.name) {
        _speak(translatedMessage, widget.language);
      }

      _scrollToBottom();
    });

    widget.socket.on('message', (data) {
      setState(() {
        messages.add({'sender': 'System', 'message': data['message']});
      });
      _scrollToBottom();
    });

    // Updated to track multiple users speaking at the same time
    widget.socket.on('user-speaking-start', (data) {
      setState(() {
        currentlySpeakingUsers.add(data['sender']);
        if (currentlySpeakingUsers.length == 1) {
          activeSpeaker = data['sender']; // Set active speaker if only one
        }
      });
    });

    widget.socket.on('user-speaking-stop', (data) {
      setState(() {
        currentlySpeakingUsers.remove(data['sender']);
        if (currentlySpeakingUsers.isEmpty) {
          activeSpeaker = null; // Reset active speaker when no one is speaking
        } else {
          activeSpeaker = currentlySpeakingUsers.first; // Update active speaker
        }
      });
    });
  }

  Future<void> _startRecognition() async {
    try {
      _recognizer = await _vosk.createRecognizer(
          model: await _loadModel(widget.language), sampleRate: 16000);
      if (_speechService == null) {
        _speechService = await _vosk.initSpeechService(_recognizer!);
        await _speechService!.start();

        _speechService!.onResult().listen((event) {
          Map<String, dynamic> jsonResponse = json.decode(event);
          String convertedText = jsonResponse['text'].toString().trim();
          if (convertedText.isNotEmpty) {
            setState(() {
              accumulatedText += " $convertedText";
            });
          }
        });
      }
    } catch (e) {
      print("Error: ${e.toString()}");
    }
  }

  Future<void> _stopRecognition() async {
    if (_speechService != null) {
      await _speechService!.stop();
      await _speechService!.dispose();
      _speechService = null;

      if (accumulatedText.isNotEmpty) {
        widget.socket.emit('send-message', {
          'roomId': widget.roomId,
          'message': accumulatedText.trim(),
          'language': widget.language,
        });
        accumulatedText = '';
      }
    }

    if (_recognizer != null) {
      await _recognizer!.dispose();
      _recognizer = null;
    }
  }

  Future<Model> _loadModel(String language) async {
    String modelPath;
    switch (language) {
      case 'English':
        modelPath = 'assets/models/vosk-model-small-en-in-0.4.zip';
        break;
      case 'French':
        modelPath = 'assets/models/vosk-model-small-fr-0.22.zip';
        break;
      case 'Hindi':
        modelPath = 'assets/models/vosk-model-small-hi-0.22.zip';
        break;
      case 'German':
        modelPath = 'assets/models/vosk-model-small-de-0.15.zip';
        break;
      default:
        modelPath = 'assets/models/vosk-model-small-en-in-0.4.zip';
        break;
    }

    final loadedModelPath = await _modelLoader.loadFromAssets(modelPath);
    return await _vosk.createModel(loadedModelPath);
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

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _showLeaveConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Leave Room'),
          content: const Text('Are you sure you want to leave the room?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Leave'),
              onPressed: () {
                widget.socket.disconnect();
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat Room: ${widget.roomId}'),
        backgroundColor: Colors.redAccent,
        elevation: 5.0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                final isSender = message['sender'] == widget.name;

                return Align(
                  alignment:
                      isSender ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin:
                        const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSender ? Colors.blue[100] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          spreadRadius: 2,
                          blurRadius: 5,
                          offset: const Offset(0, 3), // Shadow position
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: isSender
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          message['sender']!,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isSender ? Colors.blue[900] : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          message['message']!,
                          style: TextStyle(
                            fontSize: 16,
                            color: isSender ? Colors.black87 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Show the animation when one or more users are speaking
          // Show the animation when one or more users are speaking
          if (currentlySpeakingUsers.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LoadingAnimationWidget.bouncingBall(
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  if (currentlySpeakingUsers.length <= 3)
                    Text('${currentlySpeakingUsers.join(', ')} is speaking')
                  else
                    const Text('Multiple users are speaking'),
                ],
              ),
            ),
          ],

          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap:
                        (activeSpeaker == null || activeSpeaker == widget.name)
                            ? () async {
                                if (!_isRecording) {
                                  // Emit 'user-speaking-start' when the user starts recording
                                  widget.socket.emit('user-speaking-start',
                                      {'sender': widget.name});

                                  await _startRecognition();
                                  setState(() {
                                    _isRecording = true;
                                    isWaiting = true;
                                    isAnimatingDots = false;
                                  });

                                  await Future.delayed(
                                      const Duration(milliseconds: 1000));
                                  await Future.delayed(
                                      const Duration(milliseconds: 450));

                                  setState(() {
                                    isWaiting = false;
                                    isAnimatingDots = true;
                                  });
                                } else {
                                  // Emit 'user-speaking-stop' when the user stops recording
                                  widget.socket.emit('user-speaking-stop',
                                      {'sender': widget.name});

                                  await _stopRecognition();
                                  setState(() {
                                    _isRecording = false;
                                    isWaiting = false;
                                    isAnimatingDots = false;
                                  });
                                }
                              }
                            : null, // Disable tap if another user is speaking
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: (activeSpeaker == null ||
                              activeSpeaker == widget.name)
                          ? (_isRecording ? Colors.redAccent : Colors.redAccent)
                          : Colors.grey, // Set gray when mic is disabled
                      child: _isRecording
                          ? (isWaiting
                              ? LoadingAnimationWidget.inkDrop(
                                  color: Colors.white, size: 35)
                              : LoadingAnimationWidget.staggeredDotsWave(
                                  color: Colors.white, size: 35))
                          : Icon(
                              Icons.mic,
                              color: Colors.white,
                              size: 35,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
