import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestoreパッケージをインポート
import 'package:firebase_auth/firebase_auth.dart'; // FirebaseAuthパッケージをインポート
import 'package:file_picker/file_picker.dart'; // file_pickerをインポート
import 'dart:io'; // Fileクラスのためにインポート
import 'package:firebase_storage/firebase_storage.dart'; // Firebase Storageをインポート
import 'package:path/path.dart' as p; // pathパッケージをインポート (basenameのため)
import 'package:http/http.dart' as http; // httpパッケージをインポート
import 'dart:convert'; // jsonDecodeのためにインポート

class QuestionScreen extends StatefulWidget {
  const QuestionScreen({super.key});

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen> {
  final TextEditingController _textController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance; // FirebaseAuthのインスタンスを取得
  final FirebaseStorage _storage = FirebaseStorage.instance; // Firebase Storageのインスタンス
  final ScrollController _scrollController = ScrollController(); // ListViewのスクロール制御用

  String? _currentRoomId;
  String _currentRoomTitle = 'チャット'; // AppBarに表示するタイトル

  File? _selectedImage;
  String? _selectedImageName;
  File? _selectedFile;
  String? _selectedFileName;

  bool _isSendingMessage = false; // メッセージ送信中フラグ

  // 参考書選択用の変数を追加
  Map<String, dynamic>? _selectedReferenceBook;
  int? _selectedStartPage;
  int? _selectedEndPage;

  @override
  void initState() {
    super.initState();
    _loadInitialRoom();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose(); // ScrollControllerをdispose
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadInitialRoom() async {
    try {
      final querySnapshot = await _firestore.collection('rooms').orderBy('created_at', descending: true).limit(1).get();
      if (querySnapshot.docs.isNotEmpty) {
        final room = querySnapshot.docs.first;
        setState(() {
          _currentRoomId = room.id;
          _currentRoomTitle = room.data()['title'] ?? 'チャット';
        });
      } else {
        // ルームがない場合の初期表示（例：Drawerを開くように促すなど）
        setState(() {
            _currentRoomId = null; 
            _currentRoomTitle = 'ルームを選択してください';
        });
      }
    } catch (e) {
      print("初期ルームの読み込みに失敗しました: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('初期ルームの読み込みに失敗しました: $e')),
      );
    }
  }

  Future<void> _selectRoom(String roomId, String roomTitle) async {
    setState(() {
      _currentRoomId = roomId;
      _currentRoomTitle = roomTitle;
      _selectedImage = null; // ルーム変更時に選択ファイルをクリア
      _selectedImageName = null;
      _selectedFile = null;
      _selectedFileName = null;
    });
    Navigator.pop(context); // Drawerを閉じる
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }


  Future<void> _createNewRoom(String title) async {
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('タイトルを入力してください')),
      );
      return;
    }
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ルームを作成するにはログインが必要です')),
      );
      return;
    }

    try {
      final newRoomRef = await _firestore.collection('rooms').add({
        'title': title,
        'created_at': Timestamp.now(),
        'user_id': user.uid, // ログインユーザーのUIDを使用
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ルーム "$title" を作成しました')),
      );
      Navigator.pop(context); // ダイアログを閉じる
      // 新しいルームを選択状態にする
      _selectRoom(newRoomRef.id, title);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ルームの作成に失敗しました: $e')),
      );
    }
  }

  Future<void> _showCreateRoomDialog() async {
    final TextEditingController roomTitleController = TextEditingController();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('新しいルームを作成'),
          content: TextField(
            controller: roomTitleController,
            decoration: const InputDecoration(hintText: "ルーム名を入力"),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('キャンセル'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('作成'),
              onPressed: () {
                _createNewRoom(roomTitleController.text);
              },
            ),
          ],
        );
      },
    );
  }

  // 参考書選択ダイアログ
  Future<void> _showReferenceBookDialog() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('参考書を選択するにはログインが必要です')),
      );
      return;
    }
    // user_documentsから自分の教材を取得
    final userDocsSnapshot = await _firestore
        .collection('user_documents')
        .where('user_id', isEqualTo: currentUser.uid)
        .get();
    if (userDocsSnapshot.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登録済みの教材がありません')),
      );
      return;
    }
    // document_idでdocument_metadataを取得
    List<Map<String, dynamic>> allBooks = [];
    for (var userDoc in userDocsSnapshot.docs) {
      final docId = userDoc['document_id'];
      if (docId == null) continue;
      final metaSnap = await _firestore.collection('document_metadata').doc(docId).get();
      if (metaSnap.exists) {
        final data = metaSnap.data()!;
        allBooks.add({...data, 'id': docId});
      }
    }
    Map<String, dynamic>? selectedBook;
    int? startPage;
    int? endPage;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // 1. 教材一覧から選択
            if (selectedBook == null) {
              return AlertDialog(
                title: const Text('参考書を選択'),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 350,
                  child: ListView.builder(
                    itemCount: allBooks.length,
                    itemBuilder: (context, idx) {
                      final b = allBooks[idx];
                      return ListTile(
                        title: Text(b['file_name'] ?? '', overflow: TextOverflow.ellipsis),
                        subtitle: b['subject'] != null ? Text(b['subject']) : null,
                        onTap: () {
                          selectedBook = b;
                          setState(() {});
                        },
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('キャンセル'),
                  ),
                ],
              );
            }
            // 2. ページ範囲入力
            return AlertDialog(
              title: Text(selectedBook!['file_name'] ?? ''),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selectedBook!['subject'] != null)
                    Text('科目: ${selectedBook!['subject']}'),
                  Text('ページ範囲 (1〜${selectedBook!['total_pages'] ?? 1})'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '開始ページ'),
                          onChanged: (v) {
                            startPage = int.tryParse(v);
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '終了ページ'),
                          onChanged: (v) {
                            endPage = int.tryParse(v);
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                  if (startPage != null && endPage != null && (startPage! > endPage! || startPage! < 1 || endPage! > (selectedBook!['total_pages'] ?? 1)))
                    const Text('ページ範囲が不正です', style: TextStyle(color: Colors.red)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: (startPage != null && endPage != null && startPage! <= endPage! && startPage! >= 1 && endPage! <= (selectedBook!['total_pages'] ?? 1))
                      ? () {
                          setState(() {
                            _selectedReferenceBook = selectedBook;
                            _selectedStartPage = startPage;
                            _selectedEndPage = endPage;
                          });
                          Navigator.pop(context);
                        }
                      : null,
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // メッセージ送信処理
  Future<void> _sendMessage() async {
    if (_isSendingMessage) return; // 送信中の場合は重複実行を防ぐ

    final text = _textController.text.trim();
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('メッセージを送信するにはログインが必要です')),
      );
      return;
    }

    if (_currentRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('送信先のルームが選択されていません')),
      );
      return;
    }

    // 参考書context送信
    if (_selectedReferenceBook != null && _selectedStartPage != null && _selectedEndPage != null) {
      setState(() { _isSendingMessage = true; });
      try {
        await _firestore.collection('messages').add({
          'type': 'context',
          'document_id': _selectedReferenceBook!['id'],
          'start_page': _selectedStartPage,
          'end_page': _selectedEndPage,
          'room_id': _currentRoomId!,
          'user_id': currentUser.uid,
          'created_at': Timestamp.now(),
          'role': 'user',
          'content': text,
        });
        setState(() {
          _selectedReferenceBook = null;
          _selectedStartPage = null;
          _selectedEndPage = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        if (_currentRoomId != null) {
          await _callGenerateResponseMobile(_currentRoomId!);
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('参考書contextメッセージの送信に失敗しました: $e')),
        );
      } finally {
        setState(() { _isSendingMessage = false; });
      }
      return;
    }

    if (text.isEmpty && _selectedImage == null && _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('メッセージ内容がありません')),
      );
      return;
    }

    setState(() {
      _isSendingMessage = true;
    });

    String? fileUrl;
    String? fileName;
    String messageType = 'text'; // デフォルトはテキスト
    String? mimeType; // MIMEタイプを格納する変数を追加

    try {
      // 画像が選択されている場合
      if (_selectedImage != null && _selectedImageName != null) {
        messageType = 'image';
        fileName = _selectedImageName!;
        // 拡張子からMIMEタイプを決定
        String extension = p.extension(_selectedImage!.path).toLowerCase();
        if (extension == '.jpg' || extension == '.jpeg') {
          mimeType = 'image/jpeg';
        } else if (extension == '.png') {
          mimeType = 'image/png';
        } else if (extension == '.gif') {
          mimeType = 'image/gif';
        } else if (extension == '.heic' || extension == '.heif') { // HEIC/HEIF形式を追加
          mimeType = 'image/heic'; // または 'image/heif'
        }
        // 他の画像形式も必要に応じて追加
        
        final ref = _storage.ref('chat_attachments/${currentUser.uid}/$_currentRoomId/${p.basename(_selectedImage!.path)}');
        UploadTask uploadTask = ref.putFile(_selectedImage!);
        TaskSnapshot snapshot = await uploadTask;
        fileUrl = await snapshot.ref.getDownloadURL();
      }
      // ファイルが選択されている場合 (画像優先なのでelse if)
      else if (_selectedFile != null && _selectedFileName != null) {
        messageType = 'file';
        fileName = _selectedFileName!;
        // 拡張子からMIMEタイプを決定 (PDFの場合)
        String extension = p.extension(_selectedFile!.path).toLowerCase();
        if (extension == '.pdf') {
          mimeType = 'application/pdf';
        }
        // 他のファイル形式も必要に応じて追加

        final ref = _storage.ref('chat_attachments/${currentUser.uid}/$_currentRoomId/${p.basename(_selectedFile!.path)}');
        UploadTask uploadTask = ref.putFile(_selectedFile!);
        TaskSnapshot snapshot = await uploadTask;
        fileUrl = await snapshot.ref.getDownloadURL();
      }

      await _firestore.collection('messages').add({
        'content': text, // テキストが空でもfileUrlがあればOK
        'created_at': Timestamp.now(),
        'file_name': fileName, 
        'file_url': fileUrl,
        'mime_type': mimeType, // mime_typeフィールドを追加
        'role': 'user',
        'room_id': _currentRoomId!,
        'type': messageType,
        'user_id': currentUser.uid,
      });

      _textController.clear();
      setState(() {
        _selectedImage = null;
        _selectedImageName = null;
        _selectedFile = null;
        _selectedFileName = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

      // メッセージ送信成功後に関数を呼び出す
      if (_currentRoomId != null) {
        await _callGenerateResponseMobile(_currentRoomId!);
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('メッセージの送信に失敗しました: $e')),
      );
      print("メッセージ送信エラー: $e");
    } finally {
      setState(() {
        _isSendingMessage = false;
      });
    }
  }

  // Firebase Functionsを呼び出すメソッド
  Future<void> _callGenerateResponseMobile(String roomId) async {
    // !注意! こちらはローカル開発時のURLです。
    // デプロイ環境に合わせてURLを修正してください。
    // FirebaseプロジェクトIDとリージョンを適切に設定してください。
    const String projectId = "studyfellow-42d35";
    const String region = "asia-northeast1"; // generate-response-mobileのデプロイリージョン
    // final url = Uri.parse("http://127.0.0.1:5001/$projectId/$region/generateResponseMobile");
    // デプロイ後のURL例:
    final url = Uri.parse("https://asia-northeast1-$projectId.cloudfunctions.net/generateResponseMobile");

    try {
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          // 必要であればAuthorizationヘッダーなどを追加
          // "Authorization": "Bearer YOUR_ID_TOKEN",
        },
        body: jsonEncode({"room_id": roomId}),
      );

      if (response.statusCode == 200) {
        print("generateResponseMobile called successfully: ${response.body}");
        // ここで必要であればレスポンスに基づいたUI更新などを行う
      } else {
        print("Failed to call generateResponseMobile. Status code: ${response.statusCode}, Body: ${response.body}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AIの応答取得に失敗しました (HTTP ${response.statusCode})')),
        );
      }
    } catch (e) {
      print("Error calling generateResponseMobile: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AIの応答取得中にエラーが発生しました: $e')),
      );
    }
  }

  // 画像を選択する処理 (file_picker を使用)
  Future<void> _pickImage() async {
    Navigator.pop(context); // ボトムシートを閉じる
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedImage = File(result.files.single.path!);
          _selectedImageName = result.files.single.name;
          _selectedFile = null; 
          _selectedFileName = null;
        });
        // SnackBarはここでは不要かも。選択されたファイルはUIに表示するため。
      } else {
        // SnackBarも不要かも
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('画像選択エラー: $e')),
      );
      print("画像選択エラー: $e");
    }
  }

  // ファイルを選択する処理
  Future<void> _pickFile() async {
    Navigator.pop(context); // ボトムシートを閉じる
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, // カスタムタイプを指定
        allowedExtensions: ['pdf'], // pdfファイルのみを許可
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
          _selectedFileName = result.files.single.name;
          _selectedImage = null;
          _selectedImageName = null;
        });
      } 
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ファイル選択エラー: $e')),
      );
      print("ファイル選択エラー: $e");
    }
  }

  // 添付ファイルのオプションを表示するボトムシート
  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('画像を選択'),
                onTap: _pickImage,
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text('ファイルを選択'),
                onTap: _pickFile,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSelectedFileChip(String name, VoidCallback onClear) {
    return Chip(
      label: Text(name, overflow: TextOverflow.ellipsis),
      avatar: Icon(name.toLowerCase().endsWith('.jpg') || name.toLowerCase().endsWith('.jpeg') || name.toLowerCase().endsWith('.png') 
                  ? Icons.image 
                  : Icons.attach_file),
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.cancel),
    );
  }

  // メッセージアイテムのUIを構築するメソッド
  Widget _buildMessageItem(DocumentSnapshot messageDoc) {
    Map<String, dynamic> data = messageDoc.data()! as Map<String, dynamic>; 
    bool isUser = false; // デフォルトは相手（modelなど）
    final currentUser = _auth.currentUser;
    if (currentUser != null && data['user_id'] == currentUser.uid) {
      isUser = true;
    } else if (data['role'] == 'model') {
      isUser = false;
    } else {
      // user_idが一致せず、roleもmodelでない場合はログを出しておく（デバッグ用）
      // logger.warn("Unknown message role or user_id mismatch: ${messageDoc.id}");
      // デフォルトのisUserのまま（相手扱い）にするか、エラー表示にするか検討
    }
    
    String messageType = (data['type'] is String ? data['type'] : 'text') as String;
    String content = (data['content'] is String ? data['content'] : '') as String;
    String? fileUrl = data['file_url'] is String ? data['file_url'] as String? : null;
    String? fileName = data['file_name'] is String ? data['file_name'] as String? : null;

    // roleもStringであることを期待
    String role = (data['role'] is String ? data['role'] : 'user') as String;
    // isUserの再判定 (roleに基づいてより明確に)
    if (role == 'user' && currentUser != null && data['user_id'] == currentUser.uid) {
        isUser = true;
    } else if (role == 'model') {
        isUser = false;
    } else {
        // 想定外のroleの場合や、userだがID不一致の場合など。UI上は相手のメッセージとして表示される。
        print("Warning: Message ${messageDoc.id} has role '$role' and user_id '${data['user_id']}', but current user is '${currentUser?.uid}'. Displaying as other.");
        isUser = false; // 安全のため相手側の表示にする
    }

    Widget messageContent;
    switch (messageType) {
      case 'image':
        messageContent = fileUrl != null 
          ? Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6, maxHeight: 300),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: Image.network(fileUrl, fit: BoxFit.contain, 
                  loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 50),
                ), 
              )
            )
          : const Text('画像の読み込みに失敗しました');
        break;
      case 'file':
        messageContent = InkWell(
          onTap: () {
            // TODO: ファイルダウンロードまたはプレビュー処理 (url_launcherなど)
            print('File tapped: $fileUrl');
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isUser ? Colors.grey.shade300 : Colors.blue.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insert_drive_file, color: isUser ? Colors.black : Colors.blue.shade700),
                const SizedBox(width: 8),
                Flexible(child: Text(fileName ?? 'ファイル', style: TextStyle(color: isUser ? Colors.black : Colors.blue.shade700))),
              ],
            )
          )
        );
        break;
      case 'text':
      default:
        messageContent = Text(content);
        break;
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue[300] : Colors.grey[300],
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: messageContent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentRoomTitle), // 動的にタイトルを設定
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
              ),
              child: Text(
                'Rooms',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新規作成'),
              onTap: () {
                // Navigator.pop(context); // Drawerを閉じるのはダイアログ表示後の方がUXが良いかも
                _showCreateRoomDialog();
              },
            ),
            // rooms一覧をFirestoreからストリームで取得して表示
            StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('rooms').orderBy('created_at', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const ListTile(title: Text('エラーが発生しました'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const ListTile(title: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const ListTile(title: Text('ルームはありません'));
                }
                return Column(
                  children: snapshot.data!.docs.map((doc) {
                    final roomTitle = doc['title'] as String? ?? '名称未設定';
                    return ListTile(
                      title: Text(roomTitle),
                      onTap: () => _selectRoom(doc.id, roomTitle),
                      selected: _currentRoomId == doc.id,
                      selectedTileColor: Colors.blue.withOpacity(0.1),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _currentRoomId == null
                ? const Center(child: Text('チャットを開始するルームを選択または作成してください。'))
                : StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('messages')
                        .where('room_id', isEqualTo: _currentRoomId)
                        .orderBy('created_at', descending: false) // メッセージは古い順
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('エラー: ${snapshot.error}'));
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text('メッセージはまだありません。'));
                      }

                      // 新しいメッセージが追加されたときに一番下にスクロール
                      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                      return ListView.builder(
                        controller: _scrollController, // ScrollControllerを設定
                        padding: const EdgeInsets.all(8.0),
                        itemCount: snapshot.data!.docs.length,
                        itemBuilder: (context, index) {
                          DocumentSnapshot document = snapshot.data!.docs[index];
                          return _buildMessageItem(document);
                        },
                      );
                    },
                  ),
          ),
          // 選択されたファイルの表示エリア
          if (_selectedImageName != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: _buildSelectedFileChip(_selectedImageName!, () {
                setState(() {
                  _selectedImage = null;
                  _selectedImageName = null;
                });
              }),
            )
          else if (_selectedFileName != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: _buildSelectedFileChip(_selectedFileName!, () {
                setState(() {
                  _selectedFile = null;
                  _selectedFileName = null;
                });
              }),
            ),
          // 参考書範囲プレビュー
          if (_selectedReferenceBook != null && _selectedStartPage != null && _selectedEndPage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Card(
                color: Colors.orange.shade50,
                child: ListTile(
                  leading: const Icon(Icons.menu_book, color: Colors.orange),
                  title: Text(_selectedReferenceBook!['file_name'] ?? '', overflow: TextOverflow.ellipsis),
                  subtitle: Text('ページ範囲: ${_selectedStartPage}〜${_selectedEndPage}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.grey),
                    onPressed: () {
                      setState(() {
                        _selectedReferenceBook = null;
                        _selectedStartPage = null;
                        _selectedEndPage = null;
                      });
                    },
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _isSendingMessage ? null : _showAttachmentOptions, 
                ),
                IconButton(
                  icon: const Icon(Icons.menu_book),
                  onPressed: _isSendingMessage ? null : _showReferenceBookDialog,
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'メッセージを入力...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: _isSendingMessage ? null : (text) => _sendMessage(), 
                    enabled: !_isSendingMessage, // 送信中は無効化
                  ),
                ),
                IconButton(
                  icon: _isSendingMessage 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) 
                      : const Icon(Icons.send),
                  onPressed: _isSendingMessage ? null : _sendMessage, 
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 