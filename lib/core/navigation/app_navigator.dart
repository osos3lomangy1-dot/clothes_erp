import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

class AppNavigator {
  static void push(BuildContext context, String path, {Object? extra}) {
    context.push(path, extra: extra);
  }

  static void go(BuildContext context, String path, {Object? extra}) {
    context.go(path, extra: extra);
  }

  static void pop(BuildContext context) {
    context.pop();
  }

  static void replace(BuildContext context, String path, {Object? extra}) {
    context.pushReplacement(path, extra: extra);
  }
}
