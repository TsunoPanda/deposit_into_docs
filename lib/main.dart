import 'package:flutter/material.dart';
import 'ocr_page.dart'; // OCR画面をインポート！
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/docs/v1.dart' as docs;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OCR Sample App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomeScreen(), // 最初に表示される画面
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _DocsWriteExampleState createState() => _DocsWriteExampleState();
}

class _DocsWriteExampleState extends State<HomeScreen> {
  GoogleSignInAccount? _currentUser;
  String? _selectedDocumentId; // 選択されたドキュメントIDを保存する変数
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      docs.DocsApi.documentsScope, // Google Docsのスコープ
      'https://www.googleapis.com/auth/drive', // Google Driveのスコープ
    ],
  );


  String _status = '未サインイン';
  String? _ocrResult; // OCR結果を保存する変数

    @override
    void initState() {
    super.initState();
    _silentSignIn(); // アプリ起動時にサインインを試みる
    }

    Future<void> _silentSignIn() async {
        try {
            final user = await _googleSignIn.signInSilently(); // サイレントサインインを試みる
            if (user != null) {
            setState(() {
                _currentUser = user;
                _status = '自動的にサインインしました: ${user.displayName}';
            });
            } else {
            setState(() {
                _status = 'サインインしてください。';
            });
            }
        } catch (e) {
            setState(() {
            _status = 'サインインエラー: $e';
            });
        }
    }

    Future<List<Map<String, String>>> _getDocumentList() async {
        if (_currentUser == null) {
            setState(() {
            _status = 'サインインしてください。';
            });
            return [];
        }

        final authHeaders = await _currentUser!.authHeaders;
        final client = GoogleAuthClient(authHeaders);
        final driveApi = drive.DriveApi(client);

        final fileList = await driveApi.files.list(
            q: "mimeType='application/vnd.google-apps.document'",
            spaces: 'drive',
        );

        return fileList.files
                ?.map((file) => {'id': file.id!, 'name': file.name!})
                .toList() ??
            [];
    }

    Future<void> _selectDocument() async {
    final documents = await _getDocumentList();

    if (documents.isEmpty) {
        setState(() {
        _status = '利用可能なドキュメントがありません。';
        });
        return;
    }

    if(mounted){

        showDialog(
            context: context,
            builder: (context) {
            return AlertDialog(
                title: Text('ドキュメントを選択'),
                content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                    itemCount: documents.length,
                    itemBuilder: (context, index) {
                    final doc = documents[index];
                    return ListTile(
                        title: Text(doc['name']!),
                        onTap: () {
                        Navigator.pop(context, doc['id']);
                        },
                    );
                    },
                ),
                ),
            );
            },
        ).then((selectedDocId) {
            if (selectedDocId != null) {
            setState(() {
                _status = '選択されたドキュメントID: $selectedDocId';
                _selectedDocumentId = selectedDocId; // 選択されたドキュメントIDを保存
            });
            }
        });
    }
    }

  Future<void> _handleSignIn() async {
    try {
      final user = await _googleSignIn.signIn();
      if (user != null) {
        setState(() {
          _currentUser = user;
          _status = 'ログインしました: ${user.displayName}';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'サインインエラー: $e';
      });
    }
  }

  Future<void> _writeToGoogleDocs() async {
    if (_currentUser == null) {
      setState(() {
        _status = 'サインインしてください。';
      });
      return;
    }

    if (_ocrResult == null || _ocrResult!.isEmpty) {
      setState(() {
        _status = 'OCR結果がありません。';
      });
      return;
    }

    if (_selectedDocumentId == null) {
    setState(() {
      _status = 'ドキュメントを選択してください。';
    });
    return;
    }

    final authHeaders = await _currentUser!.authHeaders;
    final client = GoogleAuthClient(authHeaders);

    final docsApi = docs.DocsApi(client);

    _ocrResult = "${_ocrResult!}\n\n*************************************************************************************************************\n\n";

    final req = docs.BatchUpdateDocumentRequest(
      requests: [
        docs.Request(
          insertText: docs.InsertTextRequest(
            text: _ocrResult!, // 保存したOCR結果を挿入
            location: docs.Location(index: 1), // 先頭に挿入
          ),
        ),
      ],
    );

    await docsApi.documents.batchUpdate(req, _selectedDocumentId!);

    setState(() {
      _status += '\nDocsへの書き込みに成功しました。';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Google Docs 書き込みテスト")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_status),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _handleSignIn, // サインインボタン
              child: Text('Googleにサインイン'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                // OCRPageからテキストを取得
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => OCRPage()),
                );

                if (result != null && result is String) {
                  setState(() {
                    _ocrResult = result; // OCR結果を保存
                    _status = 'OCR結果を保存しました。';
                  });
                }
              },
              child: Text('OCRを試す'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _writeToGoogleDocs,
              child: Text('Google Docs 書き込みテスト'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
                onPressed: _selectDocument,
                child: Text('ドキュメントを選択'),
            ),
          ],
        ),
      ),
    );
  }
}

// GoogleAuthClient ヘルパー
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }

  @override
  void close() {
    _client.close();
  }
}

