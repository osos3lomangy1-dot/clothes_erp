import 'package:flutter/material.dart';

class AppNavigator {
  static void push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  static void pop(BuildContext context) {
    Navigator.of(context).pop();
  }
}
