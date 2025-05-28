import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import './edit_profile_screen.dart';
import './profile_initialization_screen.dart';
import '../data/subjects_data.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? _user;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  List<Map<String, dynamic>> _chatSettings = [];
  Map<String, List<Map<String, dynamic>>> _chatSettingsSub = {};

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (_user != null) {
      try {
        final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
            .instance
            .collection('users')
            .doc(_user!.uid)
            .get();
        if (doc.exists) {
          setState(() {
            _userData = doc.data();
          });
        }
        await _loadChatSettings();
      } catch (e) {
        print('Error loading user data: $e');
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadChatSettings() async {
    if (_user == null) return;

    try {
      // チャット設定の取得
      final settingsQuery = await FirebaseFirestore.instance
          .collection('chat_settings')
          .where('user_id', isEqualTo: _user!.uid)
          .get();

      final settings = settingsQuery.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // サブ設定の取得
      final subSettingsMap = <String, List<Map<String, dynamic>>>{};
      for (final setting in settings) {
        final subSettingsQuery = await FirebaseFirestore.instance
            .collection('chat_settings_sub')
            .where('setting_id', isEqualTo: setting['id'])
            .get();

        subSettingsMap[setting['id']] = subSettingsQuery.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      }

      setState(() {
        _chatSettings = settings;
        _chatSettingsSub = subSettingsMap;
      });
    } catch (e) {
      print('Error loading chat settings: $e');
    }
  }

  Future<void> _initializeLearningSettings() async {
    if (_user == null) return;

    try {
      // 既存の設定を確認
      final settingsQuery = await FirebaseFirestore.instance
          .collection('chat_settings')
          .where('user_id', isEqualTo: _user!.uid)
          .get();

      if (settingsQuery.docs.isNotEmpty) {
        // 既存の設定がある場合は確認ダイアログを表示
        if (!mounted) return;
        final shouldProceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('学習設定の初期化'),
            content: const Text('既存の学習設定が存在します。上書きしますか？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('上書き'),
              ),
            ],
          ),
        );

        if (shouldProceed != true) return;
      }

      // 学習設定画面に遷移
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ProfileInitializationScreen(),
        ),
      );
      await _loadChatSettings(); // 設定を再読み込み
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('学習設定の初期化に失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('プロフィール'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_userData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('プロフィール'),
        ),
        body: const Center(
          child: Text('ユーザーデータの読み込みに失敗しました。'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('プロフィール'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 基本情報
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('表示名: ${_userData!['display_name'] ?? _user?.displayName ?? 'N/A'}'),
                    const SizedBox(height: 8),
                    Text('メールアドレス: ${_userData!['email'] ?? _user?.email ?? 'N/A'}'),
                    if (_userData!['user_name'] != null) ...[
                      const SizedBox(height: 8),
                      Text('ユーザー名: ${_userData!['user_name']}'),
                    ],
                    if (_userData!['created_at'] != null) ...[
                      const SizedBox(height: 8),
                      Text('登録日: ${_formatTimestamp(_userData!['created_at'])}'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 学習設定
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('学習設定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ElevatedButton(
                          onPressed: _initializeLearningSettings,
                          child: const Text('学習設定を行う'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_chatSettings.isEmpty)
                      const Text('学習設定がありません。学習設定を行ってください。')
                    else
                      ..._chatSettings.map((setting) {
                        final subjectName = setting['subject'] as String;
                        final subSettings = _chatSettingsSub[setting['id']] ?? [];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExpansionTile(
                              title: Text(subjectName),
                              subtitle: Text('理解度: ${setting['level']}'),
                              children: [
                                if (setting['explanation']?.isNotEmpty ?? false)
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text('コメント: ${setting['explanation']}'),
                                  ),
                                if (subSettings.isNotEmpty) ...[
                                  const Divider(),
                                  ...subSettings.map((subSetting) {
                                    return ListTile(
                                      title: Text(subSetting['field']),
                                      subtitle: Text('理解度: ${subSetting['level']}'),
                                      trailing: subSetting['explanation']?.isNotEmpty ?? false
                                          ? const Icon(Icons.comment)
                                          : null,
                                    );
                                  }),
                                ],
                              ],
                            ),
                            const Divider(),
                          ],
                        );
                      }).toList(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // アクションボタン
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditProfileScreen(userData: _userData!),
                      ),
                    ).then((updated) {
                      if (updated == true) {
                        _loadUserData();
                      }
                    });
                  },
                  child: const Text('プロフィールを編集'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (mounted) {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  },
                  child: const Text('サインアウト'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final DateTime dateTime = timestamp.toDate();
    return '${dateTime.year}年${dateTime.month}月${dateTime.day}日 ${dateTime.hour}:${dateTime.minute}:${dateTime.second}';
  }
} 