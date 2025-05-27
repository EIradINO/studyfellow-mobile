import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import './document_list_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io'; // For File, if not on web
import 'package:path/path.dart' as p; // For p.basename
import 'package:flutter/foundation.dart' show kIsWeb; // To check platform

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final TextEditingController _tagController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _userId;

  List<DocumentSnapshot> _userTags = [];
  String? _selectedTagId;
  List<Map<String, dynamic>> _taggedDocuments = [];

  bool _isTagsLoading = true;
  bool _isTaggedDocumentsLoading = false;
  String? _errorMessage;

  // Controllers for the post creation form
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _startPageController = TextEditingController();
  final TextEditingController _endPageController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();

  // For time selection
  int _selectedHours = 0;
  int _selectedMinutes = 0;

  // For file picking
  List<PlatformFile> _pickedFiles = [];
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _userId = _auth.currentUser?.uid;
    if (_userId != null) {
      _loadUserTags();
    }
  }

  Future<void> _loadUserTags() async {
    if (_userId == null) return;
    setState(() {
      _isTagsLoading = true;
      _errorMessage = null;
    });
    try {
      final snapshot = await _firestore
          .collection('user_tag')
          .where('user_id', isEqualTo: _userId)
          .orderBy('created_at', descending: true)
          .get();
      setState(() {
        _userTags = snapshot.docs;
        _isTagsLoading = false;
      });
    } catch (e) {
      setState(() {
        _isTagsLoading = false;
        _errorMessage = "タグの読み込みに失敗しました: $e";
      });
      // ignore: avoid_print
      print(_errorMessage);
    }
  }

  Future<void> _addTag() async {
    if (_userId == null) {
      // ignore: avoid_print
      print("ユーザーがログインしていません。");
      return;
    }
    if (_tagController.text.isNotEmpty) {
      final newTag = _tagController.text;
      try {
        await _firestore.collection('user_tag').add({
          'name': newTag,
          'user_id': _userId,
          'created_at': FieldValue.serverTimestamp(),
        });
        _tagController.clear();
        _loadUserTags();
      } catch (e) {
        // ignore: avoid_print
        print("タグの追加に失敗しました: $e");
      }
    }
  }
  
  void _onTagSelected(String tagId) {
    setState(() {
      if (_selectedTagId == tagId) {
        _selectedTagId = null;
        _taggedDocuments = [];
        _isTaggedDocumentsLoading = false;
      } else {
        _selectedTagId = tagId;
        _loadTaggedDocuments(tagId);
      }
    });
  }

  Future<void> _loadTaggedDocuments(String tagId) async {
    if (_userId == null) return;
    setState(() {
      _isTaggedDocumentsLoading = true;
      _taggedDocuments = [];
      _errorMessage = null;
    });

    try {
      final userDocsSnapshot = await _firestore
          .collection('user_documents')
          .where('user_id', isEqualTo: _userId)
          .where('tag_id', isEqualTo: tagId)
          .get();

      if (userDocsSnapshot.docs.isEmpty) {
        setState(() {
          _isTaggedDocumentsLoading = false;
        });
        return;
      }

      List<Future<DocumentSnapshot<Map<String, dynamic>>>> metadataFutures = [];
      for (var userDoc in userDocsSnapshot.docs) {
        String documentId = userDoc['document_id'];
        metadataFutures.add(
          _firestore.collection('document_metadata').doc(documentId).get()
        );
      }
      
      final metadataSnapshots = await Future.wait(metadataFutures);
      
      List<Map<String, dynamic>> documents = [];
      for (var metaDoc in metadataSnapshots) {
        if (metaDoc.exists) {
          final data = metaDoc.data();
          if (data != null) {
            documents.add({
              'id': metaDoc.id,
              'file_name': data['file_name'] as String? ?? 'ファイル名なし',
            });
          }
        }
      }

      setState(() {
        _taggedDocuments = documents;
        _isTaggedDocumentsLoading = false;
      });

    } catch (e) {
      setState(() {
        _isTaggedDocumentsLoading = false;
        _errorMessage = "関連教材の読み込みに失敗しました: $e";
      });
      // ignore: avoid_print
      print(_errorMessage);
    }
  }

  void _showPostCreationSheet(Map<String, dynamic> document) {
    // Clear previous values
    _startPageController.clear();
    _endPageController.clear();
    _commentController.clear();
    setState(() {
      _selectedHours = 0;
      _selectedMinutes = 0;
      _pickedFiles = []; // Clear picked files
      _isUploading = false;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 20,
          left: 20,
          right: 20,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("「${document['file_name']}」の学習記録を追加", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _startPageController,
                  decoration: const InputDecoration(labelText: '開始ページ', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '開始ページを入力してください';
                    }
                    if (int.tryParse(value) == null) {
                      return '有効な数値を入力してください';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _endPageController,
                  decoration: const InputDecoration(labelText: '終了ページ', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '終了ページを入力してください';
                    }
                    final startPage = int.tryParse(_startPageController.text);
                    final endPage = int.tryParse(value);
                    if (endPage == null) {
                       return '有効な数値を入力してください';
                    }
                    if (startPage != null && endPage < startPage) {
                      return '終了ページは開始ページより後である必要があります';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(labelText: '時間', border: OutlineInputBorder()),
                        value: _selectedHours,
                        items: List.generate(24, (index) => index)
                            .map((hour) => DropdownMenuItem(
                                  value: hour,
                                  child: Text('$hour 時間'),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedHours = value;
                            });
                          }
                        },
                        validator: (value) {
                          if (value == null) return '時間を選択してください';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(labelText: '分', border: OutlineInputBorder()),
                        value: _selectedMinutes,
                        items: List.generate(60, (index) => index) // 0-59 minutes
                            .map((minute) => DropdownMenuItem(
                                  value: minute,
                                  child: Text('$minute 分'),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedMinutes = value;
                            });
                          }
                        },
                         validator: (value) {
                          if (value == null) return '分を選択してください';
                           if (_selectedHours == 0 && value == 0) {
                            return '時間は0分以上にしてください';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _commentController,
                  decoration: const InputDecoration(labelText: 'コメント', border: OutlineInputBorder()),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                _buildFilePicker(), // Add file picker UI
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isUploading ? null : () => _savePost(document['id']), // Disable button while uploading
                  child: _isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text('保存'),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _savePost(String documentId) async {
    if (_userId == null) {
      // ignore: avoid_print
      print("ユーザーがログインしていません。");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('記録を保存するにはログインが必要です。')),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      setState(() {
        _isUploading = true;
      });

      try {
        List<Map<String, String>> fileUrls = [];
        if (_pickedFiles.isNotEmpty) {
          for (PlatformFile platformFile in _pickedFiles) {
            String fileName = p.basename(platformFile.name);
            // WebではplatformFile.bytesを、モバイルではplatformFile.pathを使用します
            // Uint8List? fileBytes = platformFile.bytes; // Web
            // String? filePath = platformFile.path; // Mobile

            Reference storageRef = _storage
                .ref()
                .child('chat_files/$_userId/$fileName');

            UploadTask uploadTask;
            if (kIsWeb) {
              if (platformFile.bytes == null) continue;
              uploadTask = storageRef.putData(platformFile.bytes!,
                SettableMetadata(contentType: platformFile.extension == 'pdf' ? 'application/pdf' : 'image/${platformFile.extension}')
              );
            } else {
              if (platformFile.path == null) continue;
              uploadTask = storageRef.putFile(File(platformFile.path!),
                SettableMetadata(contentType: platformFile.extension == 'pdf' ? 'application/pdf' : 'image/${platformFile.extension}')
              );
            }
            
            TaskSnapshot snapshot = await uploadTask;
            String downloadUrl = await snapshot.ref.getDownloadURL();
            fileUrls.add({
              'name': fileName,
              'url': downloadUrl,
              'type': platformFile.extension == 'pdf' ? 'pdf' : 'image'
            });
          }
        }

        await _firestore.collection('posts').add({
          'user_id': _userId,
          'document_id': documentId,
          'start_page': int.parse(_startPageController.text),
          'end_page': int.parse(_endPageController.text),
          'duration': (_selectedHours * 60) + _selectedMinutes, // 合計分に変換
          'content': _commentController.text,
          'created_at': FieldValue.serverTimestamp(),
          'file_urls': fileUrls, // Firestoreにファイル情報を保存
        });
        if (!mounted) return;
        Navigator.pop(context); // Close the bottom sheet
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('学習記録を保存しました。')),
        );
      } catch (e) {
        // ignore: avoid_print
        print("投稿の保存に失敗しました: $e");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました: $e')),
        );
      } finally {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('記録'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DocumentListScreen()),
                );
              },
              child: const Text('教材一覧を見る'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _tagController,
              decoration: const InputDecoration(
                labelText: '新しいタグを入力',
              ),
              onSubmitted: (_) => _addTag(),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _addTag,
              child: const Text('タグを追加'),
            ),
            const SizedBox(height: 20),
            const Text("作成済みタグ:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            _buildUserTagsSection(),
            const SizedBox(height: 20),
            if (_selectedTagId != null)
              const Text("選択中のタグに紐づく教材:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            _buildTaggedDocumentsSection(),
            if (_errorMessage != null && !_isTagsLoading && !_isTaggedDocumentsLoading)
              Padding(
                padding: const EdgeInsets.only(top: 10.0),
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserTagsSection() {
    if (_isTagsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_userTags.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text("まだタグが作成されていません。"),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Wrap(
        spacing: 8.0,
        children: _userTags.map((tagDoc) {
          final tagName = tagDoc['name'] as String? ?? '名無しタグ';
          final tagId = tagDoc.id;
          return ChoiceChip(
            label: Text(tagName),
            selected: _selectedTagId == tagId,
            onSelected: (selected) {
              _onTagSelected(tagId);
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTaggedDocumentsSection() {
    if (_selectedTagId == null) {
      return const SizedBox.shrink();
    }
    if (_isTaggedDocumentsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_taggedDocuments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text("このタグに紐づく教材はありません。"),
      );
    }
    return Expanded(
      child: ListView.builder(
        itemCount: _taggedDocuments.length,
        itemBuilder: (context, index) {
          final doc = _taggedDocuments[index];
          return ListTile(
            title: Text(doc['file_name'] ?? 'ファイル名なし'),
            onTap: () {
              _showPostCreationSheet(doc);
            },
          );
        },
      ),
    );
  }

  Widget _buildFilePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _pickFiles(type: FileType.image),
                icon: const Icon(Icons.image),
                label: const Text('画像を選択'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf']),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDFを選択'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_pickedFiles.isNotEmpty)
          const Text("選択されたファイル:", style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: _pickedFiles.map((file) => Chip(
            label: Text(file.name),
            onDeleted: () {
              setState(() {
                _pickedFiles.remove(file);
              });
            },
          )).toList(),
        ),
      ],
    );
  }

  Future<void> _pickFiles({FileType type = FileType.any, List<String>? allowedExtensions}) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
        allowMultiple: true,
      );

      if (result != null) {
        setState(() {
          // 重複を避けるために、一度Setに変換してからListに戻す
          final newFiles = result.files.where((newFile) => 
            !_pickedFiles.any((existingFile) => existingFile.name == newFile.name && existingFile.size == newFile.size)
          ).toList();
          _pickedFiles.addAll(newFiles);
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('ファイル選択エラー: $e');
      if (mounted) { // Check if the widget is still in the tree
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ファイル選択中にエラーが発生しました: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _tagController.dispose();
    _startPageController.dispose();
    _endPageController.dispose();
    _commentController.dispose();
    super.dispose();
  }
} 