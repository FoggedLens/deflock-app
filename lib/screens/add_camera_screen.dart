import 'package:flutter/material.dart';

class AddCameraScreen extends StatelessWidget {
  const AddCameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Camera'),
      ),
      body: const Center(
        child: Text(
          'Add‑Camera UI coming in Stage 3',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}

