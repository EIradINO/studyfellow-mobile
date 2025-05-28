import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const EditProfileScreen({super.key, required this.userData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _displayNameController;
  late TextEditingController _userNameController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _displayNameController =
        TextEditingController(text: widget.userData['display_name'] as String? ?? '');
    _userNameController =
        TextEditingController(text: widget.userData['user_name'] as String? ?? '');
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _userNameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // ユーザーがログインしていない場合の処理
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ログインしていません。')),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'display_name': _displayNameController.text,
          'user_name': _userNameController.text,
          // photo_url や email など、他のフィールドも必要に応じて更新
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('プロフィールを更新しました。')),
          );
          Navigator.of(context).pop(true); // 更新成功を通知して前の画面に戻る
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('プロフィールの更新に失敗しました: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('プロフィール編集'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(labelText: '表示名'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '表示名を入力してください。';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _userNameController,
                decoration: const InputDecoration(labelText: 'ユーザー名'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'ユーザー名を入力してください。';
                  }
                  // 必要に応じてユーザー名のバリデーションルールを追加 (例: 英数字のみ、など)
                  return null;
                },
              ),
              const SizedBox(height: 30),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _saveProfile,
                      child: const Text('保存'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
} 