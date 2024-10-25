import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'translator_service.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';

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
  bool isAnimatingDownload = false;
  String accumulatedText = '';
  Recognizer? _recognizer;
  SpeechService? _speechService;
  final _vosk = VoskFlutterPlugin.instance();
  final _modelLoader = ModelLoader();

  // State variable to track multiple users currently speaking
  Set<String> currentlySpeakingUsers = {};

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // State variable to track the active speaker
  String? activeSpeaker;
  String? editingMessageId;
  String editingMessageContent = '';

  @override
  void initState() {
    super.initState();
    _initializeNotifications();

    widget.socket.onConnect((_) {
      print("Connected to the server");
    });

    widget.socket.on('receive-message', (data) async {
      String senderLanguage = data['senderLanguage'];
      String translatedMessage = data['message'];
      String timestamp = DateTime.now().toString();
      // Translate if sender's language is different from receiver's
      if (senderLanguage != widget.language) {
        translatedMessage = await _translatorService.translateText(
            translatedMessage, senderLanguage, widget.language);
      }

      setState(() {
        messages.add({
          'sender': data['sender'],
          'message': translatedMessage,
          'senderLanguage': senderLanguage,
          'id': data['id'],
          'timestamp': timestamp,
        });
      });

      // Play TTS for received messages only
      if (data['sender'] != widget.name) {
        _speak(translatedMessage, widget.language);
      }

      _scrollToBottom();
    });

    widget.socket.on('message', (data) {
      String timestamp = DateTime.now().toString();
      setState(() {
        messages.add({
          'sender': 'System',
          'message': data['message'],
          'timestamp': timestamp
        });
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

    widget.socket.on('message-edited', (data) async {
      String updatedMessage = data['newMessage'];
      String senderLanguage = data['senderLanguage'];
      String timestamp = DateTime.now().toString();
      // Check if sender's language is different from receiver's
      if (senderLanguage != widget.language) {
        // Translate the message to the receiver's language
        updatedMessage = await _translatorService.translateText(
            updatedMessage, senderLanguage, widget.language);
        _speak(updatedMessage, widget.language);
      }

      // Update the message in the chat box
      setState(() {
        messages = messages.map((msg) {
          if (msg['id'] == data['messageId']) {
            msg['message'] = updatedMessage; // Update the translated message
            msg['timestamp'] = timestamp; // Update the timestamp as well
          }
          return msg;
        }).toList();
      });

      // if (data['sender'] != widget.name) {
      //   _speak(updatedMessage, widget.language);
      // }
    });

    widget.socket.on('message-updated', (data) {
      setState(() {
        final updatedMessage = data.message;
        final index =
            messages.indexWhere((msg) => msg['id'] == updatedMessage.id);

        if (index != -1) {
          // Update the local message with the new content
          messages[index] = {
            ...messages[index], // Retain existing properties
            'message': updatedMessage['message'], // Update the message content
            // If you want to keep the timestamp or any other properties
            'timestamp': updatedMessage.containsKey('timestamp')
                ? updatedMessage['timestamp']
                : messages[index]
                    ['timestamp'], // Keep the old timestamp if not provided
          };
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
          'messageId': UniqueKey().toString(),
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
      // case 'German':
      //   modelPath = 'assets/models/vosk-model-small-de-0.15.zip';
      //   break;
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

  // New method to download transcriptions
  Future<void> _initializeBasicNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
        const InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
        const InitializationSettings(android: initializationSettingsAndroid);

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

    // Show notification for download start
    await flutterLocalNotificationsPlugin.show(
      0,
      'Downloading Transcription',
      'Download in progress...',
      platformChannelSpecifics,
    );

    try {
      // Check for storage permissions
      if (await Permission.storage.request().isGranted) {
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
          final String content = messages.map((t) {
            return '${t['sender']}: ${t['message']}'; // Include sender's name
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
      } else {
        // Handle permission denial
        await flutterLocalNotificationsPlugin.show(
          0,
          'Permission Denied',
          'Storage permission is required to save transcription.',
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
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _editMessage(String messageId, String updatedMessage) {
    // Emit the edited message to the server
    widget.socket.emit('edit-message', {
      'roomId': widget.roomId,
      'messageId': messageId,
      'updatedMessage': updatedMessage,
    });

    // Update the message locally
    setState(() {
      final index = messages.indexWhere((msg) => msg['id'] == messageId);
      if (index != -1) {
        messages[index]['message'] =
            updatedMessage; // Update the existing message
      }
    });
  }

  void _showEditDialog(String messageId, String currentMessage) {
    TextEditingController _editController = TextEditingController();
    _editController.text = currentMessage;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Edit Message"),
          content: TextFormField(
            controller: _editController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: "Edit your message",
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final updatedMessage = _editController.text.trim();
                if (updatedMessage.isNotEmpty) {
                  _editMessage(messageId, updatedMessage);
                  Navigator.of(context).pop(); // Close the dialog
                }
              },
              child: const Text("Send"),
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
        actions: [
          if (messages.isNotEmpty) // Check if messages are available
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8.0), // Add some padding
              child: ElevatedButton(
                onPressed: () async {
                  setState(() {
                    isAnimatingDownload = true; // Start the animation
                  });

                  // Wait for 2 seconds before starting the download
                  await Future.delayed(const Duration(seconds: 2));

                  setState(() {
                    isAnimatingDownload = false; // Stop the animation
                  });

                  _downloadTranscriptions(); // Call your download function
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(2.0),
                  backgroundColor: Colors.white, // Color for the button
                  shape: const CircleBorder(),
                  side: const BorderSide(
                    color: Colors
                        .redAccent, // Change this to your desired border color
                    width:
                        6.0, // Set the border width (reduce this value for a thinner border)
                  ), // Circular button shape
                ),
                child: isAnimatingDownload
                    ? LoadingAnimationWidget.hexagonDots(
                        color: Colors.redAccent,
                        size: 25) // Animation during download
                    : const Icon(
                        Icons.file_download,
                        size: 20, // Same size as previous
                        color: Colors.redAccent, // White icon for contrast
                      ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isSender = message['sender'] == widget.name;

                    // Format the timestamp (assuming it's stored as DateTime or String)
                    final DateTime timestamp = DateTime.parse(message[
                        'timestamp']!); // Ensure 'timestamp' is present in the message
                    final String formattedTime = DateFormat('hh:mm a')
                        .format(timestamp); // Example format: 03:45 PM

                    return Align(
                      alignment: isSender
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            vertical: 5, horizontal: 10),
                        padding: const EdgeInsets.symmetric(
                            vertical: 1, horizontal: 10),
                        decoration: BoxDecoration(
                          color: isSender ? Colors.blue[100] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              spreadRadius: 4,
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
                            // Sender name
                            Text(
                              message['sender']!,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isSender
                                    ? Colors.blue[900]
                                    : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 1),

                            // Message content
                            Text(
                              message['message']!,
                              style: TextStyle(
                                fontSize: 16,
                                color:
                                    isSender ? Colors.black87 : Colors.black54,
                              ),
                            ),

                            const SizedBox(
                                height:
                                    5), // Space between message and timestamp

                            // Timestamp
                            Text(
                              formattedTime,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors
                                    .grey, // Set a lighter color for the timestamp
                              ),
                            ),

                            // Edit icon for the sender's messages
                            if (isSender)
                              Container(
                                padding: EdgeInsets
                                    .zero, // Ensure no padding around the container
                                margin: EdgeInsets
                                    .zero, // Ensure no margin around the container
                                child: Row(
                                  mainAxisSize: MainAxisSize
                                      .min, // Minimize space taken by the row
                                  children: [
                                    IconButton(
                                      style: IconButton.styleFrom(
                                        padding: EdgeInsets
                                            .zero, // Remove padding around the button
                                        tapTargetSize: MaterialTapTargetSize
                                            .shrinkWrap, // Minimize tap area
                                      ),
                                      icon: const Icon(
                                        Icons.edit,
                                        color: Colors.red,
                                        size: 20, // Size of the icon
                                      ),
                                      onPressed: () {
                                        _showEditDialog(message['id'] ?? '',
                                            message['message'] ?? '');
                                      },
                                    ),
                                  ],
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: (activeSpeaker == null ||
                                activeSpeaker == widget.name)
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
                              ? (_isRecording
                                  ? Colors.redAccent
                                  : Colors.redAccent)
                              : Colors.grey, // Set gray when mic is disabled
                          child: _isRecording
                              ? (isWaiting
                                  ? LoadingAnimationWidget.inkDrop(
                                      color: Colors.white, size: 35)
                                  : LoadingAnimationWidget.staggeredDotsWave(
                                      color: Colors.white, size: 35))
                              : const Icon(
                                  Icons.mic,
                                  color: Colors.white,
                                  size: 35,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    // Additional buttons can be added here
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
