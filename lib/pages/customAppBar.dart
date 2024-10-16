import 'package:flutter/material.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onConversationSelected; // Callback for Conversation
  final VoidCallback onTranslationSelected; // Callback for Translation

  @override
  final Size preferredSize;

  const CustomAppBar({
    super.key,
    required this.onConversationSelected,
    required this.onTranslationSelected,
  }) : preferredSize = const Size.fromHeight(60.0);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.redAccent,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          GestureDetector(
            onTap: onTranslationSelected, // Trigger translation toggle on tap
            child: const Row(
              children: [
                Icon(Icons.translate, color: Colors.white),
                SizedBox(width: 5),
                Text(
                  'Translation',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onConversationSelected, // Trigger conversation toggle on tap
            child: const Row(
              children: [
                Icon(Icons.chat_bubble, color: Colors.white),
                SizedBox(width: 5),
                Text(
                  'Conversation',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
