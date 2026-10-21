import 'package:flutter/material.dart';

class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key, required this.docId});

  final String docId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Document $docId')),
      body: const Center(child: Text('Reader lands in Phase 2')),
    );
  }
}
