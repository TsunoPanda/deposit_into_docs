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

  /// 指定された名前のフォルダを検索し、存在しない場合は新規作成するメソッドです
  Future<String> _getOrCreateFolder(drive.DriveApi driveApi, String folderName) async {
    debugPrint('フォルダを検索中: $folderName');
    
    try {
      // 既存のフォルダを検索
      final searchQuery = "mimeType='application/vnd.google-apps.folder' and name='$folderName' and trashed=false";
      final searchResult = await driveApi.files.list(
        q: searchQuery,
        spaces: 'drive',
      );

      // フォルダが見つかった場合はそのIDを返す
      if (searchResult.files != null && searchResult.files!.isNotEmpty) {
        final existingFolder = searchResult.files!.first;
        debugPrint('既存フォルダを発見: ${existingFolder.name} (ID: ${existingFolder.id})');
        return existingFolder.id!;
      }

      // フォルダが見つからない場合は新規作成
      debugPrint('フォルダが見つからないため、新規作成します: $folderName');
      
      final newFolder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';

      final createdFolder = await driveApi.files.create(newFolder);
      debugPrint('新規フォルダを作成しました: ${createdFolder.name} (ID: ${createdFolder.id})');
      
      return createdFolder.id!;
      
    } catch (e) {
      debugPrint('フォルダの検索/作成でエラーが発生: $e');
      throw Exception('フォルダの処理に失敗しました: $e');
    }
  }

  /// 画像ファイルをGoogle Driveの指定フォルダにアップロードし、公開URLを返すメソッドです
  Future<String> _uploadImageToDriveAndGetUrl(File image, http.Client client) async {
    // Drive APIのインスタンスを作成
    final driveApi = drive.DriveApi(client);

    // ドキュメント名と同じフォルダを検索またはフォルダを作成
    String folderId = await _getOrCreateFolder(driveApi, _selectedDocumentName!);
    
    debugPrint('アップロード先フォルダID: $folderId');

    // アップロードするファイルのメタデータを作成
    var media = drive.Media(image.openRead(), await image.length());
    var driveFile = drive.File()
      ..name = 'ocr_image_${DateTime.now().millisecondsSinceEpoch}.jpg'
      ..mimeType = 'image/jpeg'
      ..parents = [folderId]; // 指定したフォルダに保存

    // ファイルをDriveにアップロード
    final uploadedFile = await driveApi.files.create(
      driveFile,
      uploadMedia: media,
    );

    // ファイルを「全員に公開」に設定
    await driveApi.permissions.create(
      drive.Permission()
        ..type = 'anyone'
        ..role = 'reader',
      uploadedFile.id!,
    );

    debugPrint('画像アップロード完了: ${uploadedFile.name}');

    // 画像の公開URLを生成して返す
    return "https://drive.google.com/uc?id=${uploadedFile.id}";
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

    if (_image == null)
    {
      setState(()
      {
        _status = '画像を撮影してください。';
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

    try
    {
      final authHeaders = await _currentUser!.authHeaders;
      final client = GoogleAuthClient(authHeaders);
      final docsApi = docs.DocsApi(client);

      // ドキュメントの現在の情報を取得して末尾の位置を調べる
      setState(() {
        _status = 'ドキュメント情報を取得中...';
      });

      // ドキュメントの現在の情報を取得して末尾の位置を調べる
      final document = await docsApi.documents.get(_selectedDocumentId!);
      final endIndex = document.body!.content!.last.endIndex! - 1; // 末尾のインデックスを取得

      debugPrint('ドキュメントの末尾インデックス: $endIndex');

      setState(() {
        _status = '画像をDriveにアップロード中...';
      });

      // テキストに区切り線を追加
      final textToInsert = "${_ocrResult!}\n\n*************************************************************************************************************\n\n";

      // ドキュメントに挿入
      setState(() {
        _status = 'ドキュメントに挿入中...';
      });

      // リクエストを作成（末尾に挿入）
      final req = docs.BatchUpdateDocumentRequest(
        requests: [
          // 1. 画像を末尾に挿入するリクエスト
          docs.Request(
            insertInlineImage: docs.InsertInlineImageRequest(
              uri: await _uploadImageToDriveAndGetUrl(_image!, client),
              location: docs.Location(index: endIndex), // ドキュメントの末尾に挿入
            ),
          ),
          // 2. テキストを末尾に挿入するリクエスト
          docs.Request(
            insertText: docs.InsertTextRequest(
              text: textToInsert,
              location: docs.Location(index: endIndex + 1), // 画像の後ろに挿入
            ),
          ),
        ],
      );

      await docsApi.documents.batchUpdate(req, _selectedDocumentId!);

      setState(() {
        _status = 'Google Docsへの書き込みが完了しました✨';
        _ocrResult = null; // 書き込み後はOCR結果をクリア
        _image = null; // 画像もクリア
      });
    }
    catch (e)
    {
      debugPrint('Docs書き込みエラー: $e');
      setState(() {
        _status = 'Docs書き込みエラー: $e';
      });
    }
  }

  Future<void> _btnCbCaptImage() async
  {
    debugPrint('=== カメラボタンが押されました ==='); // デバッグログ追加
    
    try {
      setState(() {
        _status = 'カメラを起動中...';
      });
      
      debugPrint('ImagePickerを初期化中...'); // デバッグログ
      final picker = ImagePicker();
      
      debugPrint('カメラを起動中...'); // デバッグログ
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80, // 画質を下げてメモリ使用量を削減
        maxWidth: 1024,   // 最大幅を制限
        maxHeight: 1024,  // 最大高さを制限
      );

      debugPrint('カメラから戻りました'); // デバッグログ

      if (pickedFile == null)
      {
        debugPrint('画像が選択されませんでした'); // デバッグログ
        setState(()
        {
          _status = '画像が選択されていません。';
          _image = null;
        });
        return;
      }

      debugPrint('画像ファイルパス: ${pickedFile.path}'); // デバッグログ
      
      setState(() {
        _image = File(pickedFile.path);
        _status = '画像を取得しました。OCR処理中...';
      });

      debugPrint('OCR処理開始...'); // デバッグログ
      String? extractedText = await _processImage(_image!);
      debugPrint('OCR処理完了'); // デバッグログ

      if(extractedText == null || extractedText.isEmpty)
      {
        debugPrint('OCR結果が空でした'); // デバッグログ
        setState(()
        {
          _status = 'OCRに失敗しました。';
        });
        return;
      }

      setState(()
      {
        _ocrResult = extractedText;
        _status = 'OCR完了: ${extractedText.length}文字を認識しました';
      });
      
    } catch (e) {
      debugPrint('エラーが発生しました: $e'); // デバッグログ
      setState(() {
        _status = 'エラーが発生しました: $e';
      });
    }
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("ポイしちゃお☆彡")),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDebugInfo(),
              SizedBox(height: 16),
              _buildHeaderRow(),
              SizedBox(height: 16),
              _buildCaptureButton(),
              SizedBox(height: 16),
              _buildImageContainer(),
              SizedBox(height: 16),
              _buildTextContainer(),
              SizedBox(height: 16),
              _buildPushToDocButton(),
            ],
          ),
        ),
      ),
    );
  }

// デバッグ情報表示用ウィジェットを追加
Widget _buildDebugInfo() {
  return Container(
    margin: EdgeInsets.all(8),
    padding: EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.yellow[100],
      border: Border.all(color: Colors.orange),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('🐛 デバッグ情報'),
        Text('ステータス: $_status'),
        Text('画像: ${_image != null ? "選択済み" : "未選択"}'),
        Text('OCR結果: ${_ocrResult != null ? "${_ocrResult!.length}文字" : "なし"}'),
      ],
    ),
  );
}
  // ヘッダー部分（ドキュメント選択とサインイン）
  Widget _buildHeaderRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _selectedDocumentName ?? '未選択',
              style: TextStyle(fontSize: 24),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        SizedBox(width: 8),
        _buildDocSelectButton(),
        SizedBox(width: 8),
        _buildSignInButton(),
      ],
    );
  }

  // ドキュメント選択ボタン
  Widget _buildDocSelectButton() {
    return SizedBox(
      width: imgBtnWidth,
      height: imgBtnHeight,
      child: ElevatedButton(
        onPressed: _btnCbSelectDoc,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
        ),
        child: Image.asset(
          'assets/icon/doc.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  // サインインボタン
  Widget _buildSignInButton() {
    return SizedBox(
      width: imgBtnWidth,
      height: imgBtnHeight,
      child: ElevatedButton(
        onPressed: _btnCbHandleSignIn,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
        ),
        child: Image.asset(
          'assets/icon/anonymous.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  // カメラから読み取るボタン
  Widget _buildCaptureButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: textBtnWidth,
        height: textBtnHeight,
        child: ElevatedButton(
          onPressed: _btnCbCaptImage,
          child: Text('カメラから読み取る'),
        ),
      ),
    );
  }

  // 画像表示エリア
  Widget _buildImageContainer() {
    return Container(
      width: MediaQuery.of(context).size.width - 32,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: _image != null
          ? Image.file(
              _image!,
              fit: BoxFit.contain,
            )
          : Center(
              child: Text(
                '画像がここに表示されます',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
    );
  }

  // テキスト表示エリア
  Widget _buildTextContainer() {
    return Container(
      width: MediaQuery.of(context).size.width - 32,
      height: 400,
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SingleChildScrollView(
        child: Text(
          _ocrResult ?? '読み取ったテキストがここに表示されます',
          style: TextStyle(fontSize: 14),
        ),
      ),
    );
  }

  // Google Docsへ書き込みボタン
  Widget _buildPushToDocButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: textBtnWidth,
        height: textBtnHeight,
        child: ElevatedButton(
          onPressed: _btnCbPushToDoc,
          child: Text('Google Docsへ書き込み'),
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

