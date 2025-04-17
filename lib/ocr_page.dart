// lib/ocr_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRPage extends StatefulWidget {
  const OCRPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _OCRPageState createState() => _OCRPageState();
}

class _OCRPageState extends State<OCRPage> {
  File? _image;
  String _text = '';

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera); // ギャラリーにしたい場合は `.gallery`

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });

      await _processImage(_image!);
    }
  }

  Future<void> _processImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.japanese);
    final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

    if(mounted)
    {

        setState(()
        {
            _text = recognizedText.text;
        });

        Navigator.pop(context, _text); // OCR結果を返す
    }

    textRecognizer.close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('OCR App')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            if (_image != null) Image.file(_image!),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _pickImage,
              child: Text('画像を選択'),
            ),
            SizedBox(height: 20),
            Text(
              _text,
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
