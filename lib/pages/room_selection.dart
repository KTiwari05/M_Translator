import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'chat_page.dart';

class RoomSelectionPage extends StatefulWidget {
  final String name;
  final String language;

  const RoomSelectionPage(
      {super.key, required this.name, required this.language});

  @override
  _RoomSelectionPageState createState() => _RoomSelectionPageState();
}

class _RoomSelectionPageState extends State<RoomSelectionPage> {
  late IO.Socket socket;

  @override
  void initState() {
    super.initState();
    // Initialize Socket.IO
    socket = IO.io(
        'https://ea876208-0800-472a-bcde-95b1a688d692-00-5mpn4kdzmlp0.pike.repl.co/',
        <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': false,
        });
    socket.connect();

    // Listen for socket connection
    socket.onConnect((_) {
      print('Socket connected');
    });

    socket.onConnectError((data) {
      print('Connection Error: $data');
    });

    socket.onError((data) {
      print('Socket Error: $data');
    });

    // Listen for room created event
    socket.on('room-created', (data) {
      final roomId = data['roomId'];
      print('Room created: $roomId');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            roomId: roomId,
            name: widget.name,
            language: widget.language,
            socket: socket,
          ),
        ),
      );
    });

    // Listen for room joined event
    socket.on('room-joined', (data) {
      final roomId = data['roomId'];
      print('Room joined: $roomId');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            roomId: roomId,
            name: widget.name,
            language: widget.language,
            socket: socket,
          ),
        ),
      );
    });

    // Handle room join error
    socket.on('error', (data) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data)),
      );
    });
  }

  @override
  void dispose() {
    socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room Selection'),
        backgroundColor: Colors.redAccent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Welcome card with user details
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Text(
                        'Hello, ${widget.name}!',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'You have selected ${widget.language}.',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // Create Room button with rounded corners
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 15, horizontal: 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: Colors.blueGrey[50],
                ),
                onPressed: () {
                  print("Emitting create-room event");
                  socket.emit('create-room', {
                    'name': widget.name,
                    'language': widget.language,
                  });
                },
                child: const Text(
                  'Create Room',
                  style: TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 20),

              // Join Room button with rounded corners
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 15, horizontal: 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: Colors.blueGrey[50],
                ),
                onPressed: () {
                  _showJoinRoomDialog();
                },
                child: const Text(
                  'Join Room',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Display a dialog for joining a room
  void _showJoinRoomDialog() {
    TextEditingController roomIdController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          title: const Text(
            'Join Room',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          content: TextField(
            controller: roomIdController,
            decoration: const InputDecoration(
              hintText: 'Enter Room ID',
              border: OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2.0),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                String roomId = roomIdController.text.trim();
                if (roomId.isNotEmpty) {
                  print('Emitting join-room event');
                  socket.emit('join-room', {
                    'roomId': roomId,
                    'name': widget.name,
                    'language': widget.language,
                  });
                }
              },
              child: const Text('Join'),
            ),
          ],
        );
      },
    );
  }
}
