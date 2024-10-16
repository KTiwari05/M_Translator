import 'package:flutter/material.dart';
import 'package:voicetotext/homepage.dart'; // Import your TranslatorScreen
import 'pages/user_registration.dart'; // Adjust the path as necessary
import 'pages/customAppBar.dart'; // Import your CustomAppBar

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Your App',
      theme: ThemeData(primarySwatch: Colors.red),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool isMainApp =
      true; // True for TranslatorScreen, false for UserRegistration

  // Separate methods for toggling
  void showTranslatorScreen() {
    setState(() {
      isMainApp = true;
    });
  }

  void showUserRegistrationPage() {
    setState(() {
      isMainApp = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        onConversationSelected:
            showUserRegistrationPage, // Show UserRegistration
        onTranslationSelected: showTranslatorScreen, // Show TranslatorScreen
      ),
      body: isMainApp
          ? const TranslatorScreen() // Show TranslatorScreen when true
          : const UserRegistrationPage(), // Show UserRegistrationPage when false
    );
  }
}
