import 'package:flutter/material.dart';
import 'room_selection.dart';
import 'package:http/http.dart' as http;

class UserRegistrationPage extends StatefulWidget {
  const UserRegistrationPage({super.key});

  @override
  _UserRegistrationPageState createState() => _UserRegistrationPageState();
}

class _UserRegistrationPageState extends State<UserRegistrationPage> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedLanguage = 'English';
  final List<String> languages = ['English', 'French', 'Hindi'];

  // Expiration date
  final DateTime expirationDate = DateTime(2024, 11, 01, 11, 59, 59);

  Future<bool> hasInternetConnection() async {
    try {
      final response = await http
          .get(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return true; // Internet is available
      }
    } catch (e) {
      return false; // No internet connection
    }
    return false;
  }

  // Show the no-internet connection dialog
  void showNoInternetDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('No Internet Connection'),
          content:
              const Text('Please check your network settings and try again.'),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A card for the form fields to give a clean look
                Card(
                  color: Colors.blueGrey[50],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        // Name input field with rounded borders
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Your Name',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: Colors.blue, width: 2.0),
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                          ),
                          maxLength: 30,
                        ),
                        const SizedBox(height: 20),

                        // Custom-styled Dropdown for language selection
                        InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Select Language',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 12.0, horizontal: 16.0),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedLanguage,
                              isExpanded: true,
                              icon: const Icon(Icons.arrow_drop_down,
                                  color: Colors.blue),
                              items: languages.map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(
                                    value,
                                    style: const TextStyle(
                                        fontSize: 16.0,
                                        fontWeight: FontWeight.w400),
                                  ),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                setState(() {
                                  _selectedLanguage = newValue!;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),

                        // Proceed button with rounded corners
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14.0, horizontal: 50.0),
                          ),
                          onPressed: () async {
                            // Check if the current date is before the expiration date
                            if (DateTime.now().isAfter(expirationDate)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Registration has expired.'),
                                ),
                              );
                            } else if (_nameController.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter your name'),
                                ),
                              );
                            } else {
                              // Check for internet connection
                              bool isConnected = await hasInternetConnection();
                              if (isConnected) {
                                // Navigate to the next page if internet is available
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => RoomSelectionPage(
                                      name: _nameController.text,
                                      language: _selectedLanguage,
                                    ),
                                  ),
                                );
                              } else {
                                // Show no-internet dialog if not connected
                                showNoInternetDialog();
                              }
                            }
                          },
                          child: const Text(
                            'Proceed ',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
