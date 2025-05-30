import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class PostDetailScreen extends StatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Map<String, dynamic>? postData;
  List<Map<String, dynamic>> messages = [];
  bool isLoading = true;
  String? errorMessage;
  final TextEditingController _messageController = TextEditingController();
  bool _sending = false;
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      // posts取得
      final postSnap = await FirebaseFirestore.instance.collection('posts').doc(widget.postId).get();
      if (!postSnap.exists) {
        setState(() {
          errorMessage = '投稿が見つかりませんでした。';
          isLoading = false;
        });
        return;
      }
      final post = postSnap.data()!..['id'] = postSnap.id;
      // post_messages_to_ai取得
      final msgSnap = await FirebaseFirestore.instance
          .collection('post_messages_to_ai')
          .where('post_id', isEqualTo: widget.postId)
          .orderBy('created_at', descending: false)
          .get();
      final msgs = msgSnap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      setState(() {
        postData = post;
        messages = msgs;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'データ取得に失敗しました: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final user = _auth.currentUser;
    final content = _messageController.text.trim();
    if (user == null || content.isEmpty) return;
    setState(() { _sending = true; });
    try {
      // ユーザーメッセージをFirestoreに追加
      await FirebaseFirestore.instance.collection('post_messages_to_ai').add({
        'post_id': widget.postId,
        'type': 'text',
        'content': content,
        'created_at': FieldValue.serverTimestamp(),
        'role': 'user',
        'user_id': user.uid,
      });
      _messageController.clear();
      await _loadData();
      // Cloud Functions呼び出し
      final url = Uri.parse('https://asia-northeast1-studyfellow-42d35.cloudfunctions.net/generatePostResponseMobile');
      final res = await http.post(url, headers: {'Content-Type': 'application/json'}, body: json.encode({'post_id': widget.postId}));
      if (res.statusCode == 200) {
        // AI返答はCloud Functions側で自動保存されるのでリロードだけ
        await _loadData();
      } else {
        // ignore: avoid_print
        print('AI応答取得失敗: ${res.body}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI応答取得に失敗しました')));
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('送信エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('送信に失敗しました: $e')));
      }
    } finally {
      setState(() { _sending = false; });
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '日時不明';
    return DateFormat('yyyy/MM/dd HH:mm').format(timestamp.toDate());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('投稿詳細・会話履歴')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    Expanded(child: _buildContent()),
                    _buildInputArea(),
                  ],
                ),
    );
  }

  Widget _buildContent() {
    if (postData == null) return const SizedBox();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(postData!['file_name'] ?? '教材名不明', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('コメント: ${postData!['content'] ?? ''}', style: const TextStyle(fontSize: 16)),
          const Divider(height: 32),
          const Text('会話履歴', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...messages.map((msg) => _buildMessageTile(msg)).toList(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                enabled: !_sending,
                decoration: const InputDecoration(
                  hintText: 'AIに質問する...',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _sending ? null : _sendMessage,
              child: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('送信'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageTile(Map<String, dynamic> msg) {
    final role = msg['role'] ?? 'user';
    final content = msg['content'] ?? '';
    final createdAt = msg['created_at'] as Timestamp?;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: role == 'model' ? Colors.blue[50] : Colors.grey[100],
      child: ListTile(
        leading: Icon(role == 'model' ? Icons.smart_toy : Icons.person),
        title: Text(content),
        subtitle: Text('${role == 'model' ? 'AI' : 'ユーザー'}・${_formatTimestamp(createdAt)}'),
      ),
    );
  }
} 