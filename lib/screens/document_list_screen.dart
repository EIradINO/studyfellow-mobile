import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // FirebaseAuthをインポート

class DocumentListScreen extends StatefulWidget {
  const DocumentListScreen({super.key});

  @override
  State<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance; // FirebaseAuthのインスタンス
  List<DocumentSnapshot> _documents = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _selectedSubjectPathPrefix; // Firestoreクエリ用のPathプレフィックス (e.g., "raw_documents/mathematics/")
  String? _selectedSubjectDisplay; // 表示用の科目名 (e.g., "数学")

  // 科目リストとPathプレフィックスのマッピング
  final Map<String, String> _subjectPathMap = {
    '英語': 'raw_documents/english/',
    '英検': 'raw_documents/english-test/',
    '化学': 'raw_documents/chemistry/',
    '化学基礎': 'raw_documents/chemistry-basic/',
    '現代文': 'raw_documents/modern-japanese/',
    '古典': 'raw_documents/classic-japanese/',
    '数学': 'raw_documents/mathematics/',
    '生物': 'raw_documents/biology/',
    '生物基礎': 'raw_documents/biology-basic/',
    '物理': 'raw_documents/physics/',
    '物理基礎': 'raw_documents/physics-basic/',
    '公共': 'raw_documents/public/',
    '小論文': 'raw_documents/essay/',
    '情報': 'raw_documents/information/',
    '世界史探究': 'raw_documents/world-history/',
    '日本史探究': 'raw_documents/japan-history/',
    '地理探究': 'raw_documents/geography/',
    '政治・経済': 'raw_documents/politics-economy/',
    '倫理': 'raw_documents/ethics/',
  };

  @override
  void initState() {
    super.initState();
  }

  Future<void> _loadDocuments(String pathPrefix) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _documents = [];
    });
    try {
      // pathフィールドが指定されたプレフィックスで始まるドキュメントを検索
      // '\uf8ff' は非常に高いUnicode文字で、実質的に "startsWith" の動作を実現
      final snapshot = await _firestore
          .collection('document_metadata')
          .where('path', isGreaterThanOrEqualTo: pathPrefix)
          .where('path', isLessThan: '$pathPrefix\uf8ff')
          // 必要であれば、ここでさらにorderByを追加できます。
          // その場合はpathとorderBy対象フィールドでの複合インデックスが必要になります。
          // 例: .orderBy('created_at', descending: true)
          .get();
      setState(() {
        _documents = snapshot.docs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "教材リストの読み込みに失敗しました: $e";
      });
      // ignore: avoid_print
      print(_errorMessage);
    }
  }

  void _selectSubject(String displayKey, String pathPrefix) {
    setState(() {
      _selectedSubjectDisplay = displayKey;
      _selectedSubjectPathPrefix = pathPrefix;
    });
    _loadDocuments(pathPrefix);
  }

  void _clearSubjectSelection() {
    setState(() {
      _selectedSubjectPathPrefix = null;
      _selectedSubjectDisplay = null;
      _documents = [];
      _errorMessage = null;
    });
  }

  // タグを読み込むメソッド
  Future<List<DocumentSnapshot>> _loadUserTags() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return [];

    try {
      final snapshot = await _firestore
          .collection('user_tag')
          .where('user_id', isEqualTo: currentUser.uid)
          .orderBy('created_at', descending: true)
          .get();
      return snapshot.docs;
    } catch (e) {
      // ignore: avoid_print
      print("タグの読み込みに失敗しました: $e");
      return [];
    }
  }

  // user_documents に登録するメソッド
  Future<void> _registerUserDocument(String documentId, String tagId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      // ignore: avoid_print
      print("ユーザーがログインしていません。");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("登録にはログインが必要です。")),
      );
      return;
    }

    try {
      await _firestore.collection('user_documents').add({
        'document_id': documentId,
        'tag_id': tagId,
        'user_id': currentUser.uid,
        'created_at': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("教材をタグに登録しました。")),
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // ボトムシートを閉じる
    } catch (e) {
      // ignore: avoid_print
      print("user_documents への登録に失敗しました: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("登録に失敗しました: $e")),
      );
    }
  }

  void _showTagSelectionSheet(BuildContext context, DocumentSnapshot document) {
    String? selectedTagId;
    final String documentId = document.id; // タップされた教材のドキュメントID
    final String fileName = document['file_name'] as String? ?? 'ファイル名なし';

    showModalBottomSheet(
      context: context,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return FutureBuilder<List<DocumentSnapshot>>(
              future: _loadUserTags(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(snapshot.hasError
                          ? "タグの読み込みに失敗しました。"
                          : "登録できるタグがありません。先にタグを作成してください。" ),
                    ),
                  );
                }

                final tags = snapshot.data!;

                return Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('「$fileName」に付けるタグを選択', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          itemCount: tags.length,
                          itemBuilder: (context, index) {
                            final tag = tags[index];
                            final tagName = tag['name'] as String? ?? '名称未設定';
                            final tagId = tag.id;
                            return RadioListTile<String>(
                              title: Text(tagName),
                              value: tagId,
                              groupValue: selectedTagId,
                              onChanged: (String? value) {
                                setModalState(() {
                                  selectedTagId = value;
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: const Text('キャンセル'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: selectedTagId == null
                                ? null // タグが選択されていない場合は無効化
                                : () {
                                    _registerUserDocument(documentId, selectedTagId!);
                                  },
                            child: const Text('登録'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedSubjectDisplay ?? '科目を選択'),
        leading: _selectedSubjectPathPrefix != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _clearSubjectSelection,
              )
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_selectedSubjectPathPrefix == null) {
      // 科目選択画面
      return ListView(
        children: _subjectPathMap.entries.map((entry) {
          return ListTile(
            title: Text(entry.key),
            onTap: () => _selectSubject(entry.key, entry.value),
          );
        }).toList(),
      );
    }

    // 教材リスト表示画面
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () {
                  if (_selectedSubjectPathPrefix != null) {
                    _loadDocuments(_selectedSubjectPathPrefix!);
                  }
                },
                child: const Text('再試行'),
              )
            ],
          ),
        ),
      );
    }
    if (_documents.isEmpty) {
      return const Center(child: Text('この科目の教材データがありません。'));
    }

    return ListView.builder(
      itemCount: _documents.length,
      itemBuilder: (context, index) {
        final doc = _documents[index];
        final fileName = doc['file_name'] as String? ?? 'ファイル名なし';
        return ListTile(
          title: Text(fileName),
          onTap: () {
            _showTagSelectionSheet(context, doc); // ListTileタップでボトムシート表示
          },
        );
      },
    );
  }
} 