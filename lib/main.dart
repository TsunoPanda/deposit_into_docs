import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/docs/v1.dart' as docs;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

const double imgBtnOffsetX = 16; // ボタンのX座標オフセット
const double imgBtnOffsetY = 16; // ボタンのY座標オフセット
const double imgBtnWidth = 48; // ボタンの幅
const double imgBtnHeight = 48; // ボタンの高さ

const double textBtnWidth = 120; // ボタンの幅
const double textBtnHeight = 60; // ボタンの高さ

void main()
{
  runApp(MyApp());
}

class MyApp extends StatelessWidget
{
  const MyApp({super.key});

  @override
  Widget build(BuildContext context)
  {
    return MaterialApp
    (
      title: 'OCR Sample App',
      theme: ThemeData
      (
        primarySwatch: Colors.blue,
      ),
      home: HomeScreen(), // 最初に表示される画面
    );
  }
}

class HomeScreen extends StatefulWidget
{
  const HomeScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _DocsWriteExampleState createState() => _DocsWriteExampleState();
}

class _DocsWriteExampleState extends State<HomeScreen>
{
  File? _image;

  GoogleSignInAccount? _currentUser;
  String? _selectedDocumentId; // 選択されたドキュメントIDを保存する変数
  String? _selectedDocumentName; // 選択されたドキュメント名を保存する変数
  final GoogleSignIn _googleSignIn = GoogleSignIn
  (
    scopes:
    [
      docs.DocsApi.documentsScope, // Google Docsのスコープ
      'https://www.googleapis.com/auth/drive', // Google Driveのスコープ
    ],
  );


  String _status = '未サインイン';
  String? _ocrResult; // OCR結果を保存する変数

  @override
  void initState()
  {
    super.initState();
    _silentSignIn(); // アプリ起動時にサインインを試みる
  }

    Future<void> _silentSignIn() async
    {
      try
      {
          final user = await _googleSignIn.signInSilently(); // サイレントサインインを試みる
          if (user != null)
          {
            setState(()
            {
              _currentUser = user;
              _status = '自動的にサインインしました: ${user.displayName}';
            });
          }
          else
          {
            setState(()
            {
              _status = 'サインインしてください。';
            });
          }
      }
      catch (e)
      {
        setState(()
        {
          _status = 'サインインエラー: $e';
        });
      }
    }

    Future<List<Map<String, String>>> _getDocumentList() async
    {
        if (_currentUser == null)
        {
            setState(()
            {
              _status = 'サインインしてください。';
            });
            return [];
        }

        final authHeaders = await _currentUser!.authHeaders;
        final client = GoogleAuthClient(authHeaders);
        final driveApi = drive.DriveApi(client);

        final fileList = await driveApi.files.list
        (
          q: "mimeType='application/vnd.google-apps.document'",
          spaces: 'drive',
        );

        return fileList.files?.map((file) => {'id': file.id!, 'name': file.name!}).toList() ?? [];
    }

    Future<void> _btnCbSelectDoc() async
    {
      final documents = await _getDocumentList();

      if (documents.isEmpty)
      {
          setState(()
          {
            _status = '利用可能なドキュメントがありません。';
          });
          return;
      }

      if(mounted)
      {
        showDialog
        (
          context: context,
          builder: (context)
          {
            return AlertDialog
            (
              title: Text('ドキュメントを選択'),
              content: SizedBox
              (
                width: double.maxFinite,
                child: ListView.builder
                (
                  itemCount: documents.length,
                  itemBuilder: (context, index)
                  {
                    final doc = documents[index];
                    return ListTile
                    (
                      title: Text(doc['name']!),
                      onTap: ()
                      {
                        Navigator.pop(context, doc['id']);
                      },
                    );
                  },
                ),
              ),
            );
          },
        ).then((selectedDocId)
        {
          if (selectedDocId != null)
          {
            setState(()
            {
              _status = '選択されたドキュメントID: $selectedDocId';
              _selectedDocumentId = selectedDocId; // 選択されたドキュメントIDを保存
              _selectedDocumentName = documents.firstWhere((doc) => doc['id'] == selectedDocId)['name']; // 選択されたドキュメント名を保存
            });
          }
        });
      }
    }

  Future<void> _btnCbHandleSignIn() async
  {
    try
    {
      final user = await _googleSignIn.signIn();
      if (user != null)
      {
        setState(()
        {
          _currentUser = user;
          _status = 'ログインしました: ${user.displayName}';
        });
      }
    }
    catch (e)
    {
      setState(()
      {
        _status = 'サインインエラー: $e';
      });
    }
  }

  Future<void> _btnCbPushToDoc() async
  {
    if (_currentUser == null)
    {
      setState(()
      {
        _status = 'サインインしてください。';
      });
      return;
    }

    if (_ocrResult == null || _ocrResult!.isEmpty)
    {
      setState(()
      {
        _status = 'OCR結果がありません。';
      });
      return;
    }

    if (_selectedDocumentId == null)
    {
      setState(()
      {
        _status = 'ドキュメントを選択してください。';
      });
      return;
    }

    final authHeaders = await _currentUser!.authHeaders;
    final client = GoogleAuthClient(authHeaders);

    final docsApi = docs.DocsApi(client);

    _ocrResult = "${_ocrResult!}\n\n*************************************************************************************************************\n\n";

    final req = docs.BatchUpdateDocumentRequest
    (
      requests:
      [
        docs.Request
        (
          insertText: docs.InsertTextRequest
          (
            text: _ocrResult!, // 保存したOCR結果を挿入
            location: docs.Location(index: 1), // 先頭に挿入
          ),
        ),
      ],
    );

    await docsApi.documents.batchUpdate(req, _selectedDocumentId!);

    setState(()
    {
      _status += '\nDocsへの書き込みに成功しました。';
      _ocrResult = null; // 書き込み後はOCR結果をクリア
    });
  }

  Future<void> _btnCbCaptImage() async
  {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera); // ギャラリーにしたい場合は `.gallery`

    if (pickedFile == null)
    {
      setState(()
      {
        _status = '画像が選択されていません。';
        _image = null; // 画像をクリア
      });
      return;
    }

    _image = File(pickedFile.path);

    String? extractedText = await _processImage(_image!);

    if(extractedText == null || extractedText.isEmpty)
    {
      setState(()
      {
        _status = 'OCRに失敗しました。';
      });
      return;
    }

    setState(()
    {
      _ocrResult = extractedText; // OCR結果を保存
      _status = 'OCR OK';
    });
  }

  Future<String?> _processImage(File imageFile) async
  {
    final inputImage = InputImage.fromFile(imageFile);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.japanese);
    final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

    textRecognizer.close();
    return recognizedText.text;
  }

@override
  Widget build(BuildContext context)
  {
    return Scaffold
    (
      appBar: AppBar(title: Text("ポイしちゃお☆彡")),
      body: SingleChildScrollView // 縦スクロールを有効にする
      (
        child: ConstrainedBox
        (
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height*2, // 画面の高さに合わせる
          ),
          child: IntrinsicHeight // 子ウィジェットの高さに合わせる
          (
            child: Stack
            (
              children: 
              [
                Positioned
                (
                  top: imgBtnOffsetY + imgBtnHeight + 16, // 上からの距離
                  right: 16, // 右からの距離
                  child: Column
                  (
                    crossAxisAlignment: CrossAxisAlignment.end, // 子ウィジェットを右寄せ
                    children:
                    [
                      SizedBox
                      (
                        width: textBtnWidth, // ボタンの幅
                        height: textBtnHeight, // ボタンの高さ
                        child: ElevatedButton
                        (
                          onPressed: _btnCbCaptImage,
                          child: Text('カメラから読み取る'),
                        ),
                      ),
                      SizedBox(height: 16), // ボタンと画像表示エリアの間の余白
                      Container
                      (
                        width: MediaQuery.of(context).size.width - 32, // 画面幅から左右の余白を引いたサイズ
                        height: 200, // 画像表示エリアの高さ
                        decoration: BoxDecoration
                        (
                          color: Colors.grey[200], // 背景色
                          border: Border.all(color: Colors.grey), // 枠線
                          borderRadius: BorderRadius.circular(4), // 角を丸くする
                        ),
                        child: _image != null
                            ? Image.file
                            (
                                _image!, // 選択された画像を表示
                                fit: BoxFit.contain, // 画像をエリアにフィットさせる
                            )
                            : Center
                            (
                                child: Text
                                (
                                  '画像がここに表示されます', // プレースホルダーのテキスト
                                  style: TextStyle(color: Colors.grey, fontSize: 16), // テキストのスタイル
                                ),
                            ),
                      ),
                      SizedBox(height: 16), // 画像表示エリアとテキストボックスの間の余白
                      Container
                      (
                        width: MediaQuery.of(context).size.width - 32, // テキストボックスの幅を画面に合わせる
                        height: 400, // テキストボックスの高さを固定
                        padding: EdgeInsets.all(8), // 内側の余白
                        decoration: BoxDecoration
                        (
                          color: Colors.white, // 背景色
                          border: Border.all(color: Colors.grey), // 枠線
                          borderRadius: BorderRadius.circular(4), // 角を丸くする
                        ),
                        child: SingleChildScrollView
                        (
                          child: Text
                          (
                            _ocrResult ?? '読み取ったテキストがここに表示されます', // OCR結果を表示
                            style: TextStyle(fontSize: 14), // テキストのスタイル
                          ),
                        ),
                      ),
                      SizedBox(height: 16), // テキストボックスと次のボタンの間の余白
                      SizedBox
                      (
                        width: textBtnWidth, // ボタンの幅
                        height: textBtnHeight, // ボタンの高さ
                        child: ElevatedButton
                        (
                          onPressed: _btnCbPushToDoc,
                          child: Text('Google Docsへ書き込み'),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned
                (
                  top: imgBtnOffsetY, // 上からの距離
                  left: imgBtnOffsetX, // 左からの距離
                  right: imgBtnOffsetX, // 右からの距離
                  child: Row( children:
                  [
                    // ドキュメント名を表示するテキストボックス
                    Expanded
                    (
                      child: Container
                      (
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), // 内側の余白
                        decoration: BoxDecoration
                        (
                          color: Colors.white, // 背景色
                          border: Border.all(color: Colors.grey), // 枠線
                          borderRadius: BorderRadius.circular(4), // 角を丸くする
                        ),
                        child: Text
                        (
                          _selectedDocumentName != null ? '$_selectedDocumentName' : '未選択', // 表示するテキスト
                          style: TextStyle(fontSize: 24), // テキストのスタイル
                          overflow: TextOverflow.ellipsis, // テキストが長い場合は省略
                        ),
                      ),
                    ),
                    SizedBox
                    (
                      width: imgBtnWidth, // ボタンの幅
                      height: imgBtnHeight, // ボタンの高さ
                      child: ElevatedButton
                      (
                        onPressed: _btnCbSelectDoc,
                        style: ElevatedButton.styleFrom
                        (
                          padding: EdgeInsets.zero, // 余白をゼロに設定
                          shape: RoundedRectangleBorder
                          (
                            borderRadius: BorderRadius.zero, // 角をとがらせる
                          ),
                        ),
                        child: Image.asset
                        (
                          'assets/icon/doc.png', // 画像のパスを指定
                          fit: BoxFit.cover, // 画像をボタン全体にフィット
                        ),
                      ),
                    ),            
                    SizedBox
                    (
                      width: imgBtnWidth, // ボタンの幅
                      height: imgBtnHeight, // ボタンの高さ
                      child: ElevatedButton
                      (
                        onPressed: _btnCbHandleSignIn, // サインインボタン
                        style: ElevatedButton.styleFrom
                        (
                          padding: EdgeInsets.zero, // 余白をゼロに設定
                          shape: RoundedRectangleBorder
                          (
                            borderRadius: BorderRadius.zero, // 角をとがらせる
                          ),
                        ),
                        child: Image.asset
                        (
                          'assets/icon/anonymous.png', // 画像のパスを指定
                          fit: BoxFit.cover, // 画像をボタン全体にフィット
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
// GoogleAuthClient ヘルパー
class GoogleAuthClient extends http.BaseClient
{
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request)
  {
    return _client.send(request..headers.addAll(_headers));
  }

  @override
  void close()
  {
    _client.close();
  }
}

