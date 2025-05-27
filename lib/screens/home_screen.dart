import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Date formatting
import 'package:url_launcher/url_launcher.dart'; // For launching URLs

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _userId;

  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _userId = _auth.currentUser?.uid;
    if (_userId != null) {
      _loadPosts();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = "ログインしていません。投稿を表示できません。";
      });
    }
  }

  Future<void> _loadPosts() async {
    if (_userId == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final postsSnapshot = await _firestore
          .collection('posts')
          .where('user_id', isEqualTo: _userId)
          .orderBy('created_at', descending: true)
          .get();

      if (postsSnapshot.docs.isEmpty) {
        setState(() {
          _posts = [];
          _isLoading = false;
        });
        return;
      }

      List<Map<String, dynamic>> loadedPosts = [];
      for (var postDoc in postsSnapshot.docs) {
        final postData = postDoc.data();
        postData['id'] = postDoc.id; // Add post ID for potential future use (e.g., navigation, deletion)

        DocumentSnapshot<Map<String, dynamic>>? metadataDoc;
        if (postData['document_id'] != null && (postData['document_id'] as String).isNotEmpty) {
           metadataDoc = await _firestore
              .collection('document_metadata')
              .doc(postData['document_id'])
              .get();
        }
        
        String fileName = metadataDoc != null && metadataDoc.exists && metadataDoc.data()!['file_name'] != null
            ? metadataDoc.data()!['file_name']
            : '教材名不明';
        
        postData['file_name'] = fileName;
        loadedPosts.add(postData);
      }

      setState(() {
        _posts = loadedPosts;
        _isLoading = false;
      });
    } catch (e) {
      // ignore: avoid_print
      print('投稿の読み込みエラー: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = "投稿の読み込みに失敗しました: $e";
      });
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '日時不明';
    return DateFormat('yyyy/MM/dd HH:mm').format(timestamp.toDate());
  }

  String _formatDuration(int? totalMinutes) {
    if (totalMinutes == null || totalMinutes < 0) return '時間不明';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0 && minutes > 0) {
      return '$hours時間$minutes分';
    } else if (hours > 0) {
      return '$hours時間';
    } else {
      return '$minutes分';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ホーム (学習記録)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPosts,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 16)),
        ),
      );
    }

    if (_posts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('まだ学習記録がありません。', style: TextStyle(fontSize: 16)),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPosts,
      child: ListView.builder(
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          final post = _posts[index];
          final createdAt = post['created_at'] as Timestamp?;
          final duration = post['duration'] as int?;
          final startPage = post['start_page'] as int?;
          final endPage = post['end_page'] as int?;
          final content = post['content'] as String?;
          final fileUrls = (post['file_urls'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post['file_name'] ?? '教材名不明',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(_formatTimestamp(createdAt), style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 16, color: Colors.blueAccent),
                      const SizedBox(width: 4),
                      Text('勉強時間: ${_formatDuration(duration)}', style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (startPage != null && endPage != null)
                    Row(
                      children: [
                        const Icon(Icons.menu_book, size: 16, color: Colors.green),
                        const SizedBox(width: 4),
                        Text('範囲: P.$startPage - P.$endPage', style: const TextStyle(color: Colors.green)),
                      ],
                    ),
                  if (content != null && content.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('コメント:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
                    const SizedBox(height: 4),
                    Text(content, style: TextStyle(fontSize: 15, color: Colors.grey[800])),
                  ],
                  if (fileUrls.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('添付ファイル:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
                    const SizedBox(height: 4),
                    _buildAttachmentList(fileUrls),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAttachmentList(List<Map<String, dynamic>> fileUrls) {
    return Wrap(
      spacing: 8.0,
      runSpacing: 4.0,
      children: fileUrls.map((fileData) {
        final String name = fileData['name'] as String? ?? '不明なファイル';
        final String url = fileData['url'] as String? ?? '';
        final String type = fileData['type'] as String? ?? ''; // 'image' or 'pdf'

        IconData iconData = Icons.insert_drive_file;
        if (type == 'image') {
          iconData = Icons.image;
        } else if (type == 'pdf') {
          iconData = Icons.picture_as_pdf;
        }

        return ActionChip(
          avatar: Icon(iconData, size: 16),
          label: Text(name, overflow: TextOverflow.ellipsis),
          onPressed: () => _launchURL(url),
        );
      }).toList(),
    );
  }

  Future<void> _launchURL(String urlString) async {
    final Uri? url = Uri.tryParse(urlString);
    if (url != null && await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      // ignore: avoid_print
      print('Could not launch $urlString');
      if (mounted) { // Check if the widget is still in the tree
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ファイルを開けませんでした: $urlString')),
        );
      }
    }
  }
} 