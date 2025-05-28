import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/subjects_data.dart'; // 科目データをインポート

class ProfileInitializationScreen extends StatefulWidget {
  const ProfileInitializationScreen({super.key});

  @override
  State<ProfileInitializationScreen> createState() =>
      _ProfileInitializationScreenState();
}

class _ProfileInitializationScreenState extends State<ProfileInitializationScreen> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 1;
  bool _isLoading = true;
  bool _isSaving = false;

  // Step 1: User data
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _userNameController = TextEditingController();

  // Step 2: Subject selection
  Map<String, bool> _selectedSubjects = {};

  // Step 3: Subject details
  Map<String, int> _subjectComprehensions = {};
  Map<String, TextEditingController> _subjectCommentControllers = {};
  Map<String, Map<String, int>> _fieldComprehensions = {};
  Map<String, Map<String, TextEditingController>> _fieldCommentControllers = {};
  Map<String, Map<String, bool>> _expandedFields = {}; // 分野の展開状態を管理

  int _currentSubjectSetupIndex = 0; // Step 3 で設定中の科目のインデックス

  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    // 科目データの初期化
    SUBJECTS_DATA.forEach((categoryKey, categoryValue) {
      (categoryValue['subjects'] as List<Map<String, dynamic>>).forEach((subject) {
        final subjectName = subject['name'] as String;
        _selectedSubjects[subjectName] = false;
        _subjectComprehensions[subjectName] = 1;
        _subjectCommentControllers[subjectName] = TextEditingController();
        _fieldComprehensions[subjectName] = {};
        _fieldCommentControllers[subjectName] = {};
        _expandedFields[subjectName] = {};
        (subject['fields'] as List<String>).forEach((field) {
          _fieldComprehensions[subjectName]![field] = 1;
          _fieldCommentControllers[subjectName]![field] = TextEditingController();
          _expandedFields[subjectName]![field] = false;
        });
      });
    });
  }

  Future<void> _loadInitialData() async {
    _currentUser = FirebaseAuth.instance.currentUser;
    if (_currentUser == null) {
      // ログインしていない場合はエラー処理またはログイン画面へ誘導
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ログインしていません。再度ログインしてください。')),
        );
        // 例: Navigator.of(context).pushReplacementNamed('/login');
      }
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data()!;
        _displayNameController.text = data['display_name'] as String? ?? '';
        _userNameController.text = data['user_name'] as String? ?? '';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ユーザー情報の取得に失敗しました: $e')),
        );
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

 @override
  void dispose() {
    _displayNameController.dispose();
    _userNameController.dispose();
    _subjectCommentControllers.forEach((_, controller) => controller.dispose());
    _fieldCommentControllers.forEach((_, fieldMap) {
      fieldMap.forEach((_, controller) => controller.dispose());
    });
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == 1) {
      if (_formKey.currentState!.validate()) {
        setState(() {
          _currentStep = 2;
        });
      }
    } else if (_currentStep == 2) {
      // 選択された科目があるか確認
      if (_selectedSubjects.values.where((isSelected) => isSelected).isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('学習する科目を1つ以上選択してください。')),
        );
        return;
      }
      setState(() {
        _currentStep = 3;
        _currentSubjectSetupIndex = 0; // 最初の選択科目から設定開始
      });
    } else if (_currentStep == 3) {
        // 現在設定中の科目の処理は _nextSubjectSetup で行う
        _nextSubjectSetup();
    }
  }

  void _previousStep() {
    if (_currentStep > 1) {
      setState(() {
        _currentStep--;
      });
    }
  }

  List<String> get _currentlySelectedSubjectNames {
    return _selectedSubjects.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
  }

  void _nextSubjectSetup() {
    final selectedSubjectNames = _currentlySelectedSubjectNames;
    if (_currentSubjectSetupIndex < selectedSubjectNames.length - 1) {
      setState(() {
        _currentSubjectSetupIndex++;
      });
    } else {
      // 全ての選択科目の設定が完了したら保存処理へ
      _saveProfileData();
    }
  }

  void _previousSubjectSetup() {
    if (_currentSubjectSetupIndex > 0) {
      setState(() {
        _currentSubjectSetupIndex--;
      });
    } else {
        // 科目設定の最初の科目の「戻る」はステップ2（科目選択）へ
        setState(() {
            _currentStep = 2;
        });
    }
  }

  Future<void> _saveProfileData() async {
    if (_currentUser == null) return;
    setState(() {
      _isSaving = true;
    });

    try {
      // 1. Update users collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .set({
        'display_name': _displayNameController.text,
        'user_name': _userNameController.text,
        'user_id': _currentUser!.uid,
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Firestoreバッチ処理の準備
      final batch = FirebaseFirestore.instance.batch();
      final userChatSettingsCollection = FirebaseFirestore.instance.collection('chat_settings');
      final userChatSettingsSubCollection = FirebaseFirestore.instance.collection('chat_settings_sub');

      // 既存の科目の設定を削除
      final existingSettingsQuery = await userChatSettingsCollection.where('user_id', isEqualTo: _currentUser!.uid).get();
      for (final doc in existingSettingsQuery.docs) {
        final existingSubSettingsQuery = await userChatSettingsSubCollection.where('setting_id', isEqualTo: doc.id).get();
        for (final subDoc in existingSubSettingsQuery.docs) {
          batch.delete(subDoc.reference);
        }
        batch.delete(doc.reference);
      }

      // 2. Add user_chat_settings
      for (final subjectName in _currentlySelectedSubjectNames) {
        final settingRef = userChatSettingsCollection.doc();
        batch.set(settingRef, {
          'user_id': _currentUser!.uid,
          'subject': subjectName,
          'level': _subjectComprehensions[subjectName] ?? 1,
          'explanation': _subjectCommentControllers[subjectName]!.text,
          'created_at': FieldValue.serverTimestamp(),
        });

        // 3. Add user_chat_settings_sub
        final subjectData = SUBJECTS_DATA.values
            .expand((category) => category['subjects'] as List<Map<String, dynamic>>)
            .firstWhere((s) => s['name'] == subjectName, orElse: () => {});

        if (subjectData.isNotEmpty && subjectData.containsKey('fields')) {
          for (final fieldName in subjectData['fields'] as List<String>) {
            final subSettingRef = userChatSettingsSubCollection.doc();
            batch.set(subSettingRef, {
              'setting_id': settingRef.id,
              'field': fieldName,
              'level': _fieldComprehensions[subjectName]![fieldName] ?? 1,
              'explanation': _fieldCommentControllers[subjectName]![fieldName]!.text,
              'user_id': _currentUser!.uid,
              'created_at': FieldValue.serverTimestamp(),
            });
          }
        }
      }
      await batch.commit();

      if (!mounted) return; // ウィジェットが破棄されている場合は処理を中断

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('プロフィール情報を保存しました。')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return; // ウィジェットが破棄されている場合は処理を中断

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('プロフィールの保存に失敗しました: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('プロフィール設定')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('プロフィール設定 - ステップ $_currentStep'),
        leading: _currentStep > 1 && !_isSaving
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _currentStep == 3 ? _previousSubjectSetup : _previousStep,
              )
            : null,
      ),
      body: Stepper(
        currentStep: _currentStep -1, // Stepperのindexは0から始まるため
        onStepTapped: (step) {
          // タップでの直接移動はさせないか、バリデーションを入れる
        },
        onStepContinue: _isSaving ? null : _nextStep, // 保存中は次へ進めない
        onStepCancel: _currentStep > 1 && !_isSaving ? (_currentStep == 3 ? _previousSubjectSetup : _previousStep) : null,
        controlsBuilder: (BuildContext context, ControlsDetails details) {
            return Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Row(
                children: <Widget>[
                    if (_currentStep < 3 || (_currentStep == 3 && _currentlySelectedSubjectNames.isNotEmpty && _currentSubjectSetupIndex < _currentlySelectedSubjectNames.length -1 ) )
                    ElevatedButton(
                        onPressed: details.onStepContinue,
                        child: Text(_currentStep == 3 ? '次の科目へ' : '次へ'),
                    ),
                    if (_currentStep == 3 && _currentlySelectedSubjectNames.isNotEmpty && _currentSubjectSetupIndex == _currentlySelectedSubjectNames.length -1 )
                    ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfileData, // details.onStepContinue はここでは _saveProfileData を直接呼び出す
                        child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white,)) : const Text('保存'),
                    ),
                    if (_currentStep > 1)
                    TextButton(
                        onPressed: details.onStepCancel,
                        child: const Text('戻る'),
                    ),
                ],
                ),
            );
        },
        steps: <Step>[
          Step(
            title: const Text('基本情報'),
            content: _buildStep1(),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('科目選択'),
            content: _buildStep2(),
            isActive: _currentStep >= 2,
             state: _currentStep > 2 ? StepState.complete : (_currentStep == 2 ? StepState.indexed : StepState.disabled),
          ),
          Step(
            title: const Text('詳細設定'),
            content: _buildStep3(),
            isActive: _currentStep >= 3,
            state: _currentStep == 3 && _isSaving ? StepState.editing : (_currentStep == 3 ? StepState.indexed : StepState.disabled), 
          ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return Form(
      key: _formKey, // ステップ1のフォームにキーを割り当てる
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
          const SizedBox(height: 16),
          TextFormField(
            controller: _userNameController,
            decoration: const InputDecoration(labelText: 'ユーザー名'),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'ユーザー名を入力してください。';
              }
              // TODO: ユーザー名の一意性チェック (Firestoreと連携)
              return null;
            },
          ),
          const SizedBox(height: 16),
           Text(
            'ユーザー名は一意である必要があります',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: SUBJECTS_DATA.entries.map((categoryEntry) {
          final categoryName = categoryEntry.value['name'] as String;
          final subjects = categoryEntry.value['subjects'] as List<Map<String, dynamic>>;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
                child: Text(
                  categoryName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ...subjects.map((subject) {
                final subjectName = subject['name'] as String;
                return CheckboxListTile(
                  title: Text(subjectName),
                  value: _selectedSubjects[subjectName],
                  onChanged: (bool? newValue) {
                    setState(() {
                      _selectedSubjects[subjectName] = newValue ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }).toList(),
              const Divider(),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStep3() {
    if (_currentlySelectedSubjectNames.isEmpty) {
      return const Center(
        child: Text('設定する科目が選択されていません。前のステップに戻って科目を選択してください。'),
      );
    }
    if (_currentSubjectSetupIndex >= _currentlySelectedSubjectNames.length) {
        // 通常ここには到達しないはずだが、念のため
        return const Center(child: Text('すべての科目の設定が完了しました。'));
    }

    final currentSubjectName = _currentlySelectedSubjectNames[_currentSubjectSetupIndex];
    final subjectData = SUBJECTS_DATA.values
        .expand((category) => category['subjects'] as List<Map<String, dynamic>>)
        .firstWhere((s) => s['name'] == currentSubjectName, orElse: () => {});
    final fields = subjectData.isNotEmpty && subjectData.containsKey('fields')
        ? subjectData['fields'] as List<String>
        : <String>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '「$currentSubjectName」の詳細設定 (${_currentSubjectSetupIndex + 1}/${_currentlySelectedSubjectNames.length})',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Text('総合的な理解度', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: (_subjectComprehensions[currentSubjectName] ?? 1).toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: (_subjectComprehensions[currentSubjectName] ?? 1).toString(),
            onChanged: (double value) {
              setState(() {
                _subjectComprehensions[currentSubjectName] = value.toInt();
              });
            },
          ),
          TextFormField(
            controller: _subjectCommentControllers[currentSubjectName],
            decoration: const InputDecoration(
              labelText: 'この科目についてのコメント (任意)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          if (fields.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('分野ごとの理解度', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...fields.map((fieldName) {
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6.0),
                child: ExpansionTile(
                  key: ValueKey('$currentSubjectName-$fieldName'),
                  title: Text(fieldName),
                  initiallyExpanded: _expandedFields[currentSubjectName]![fieldName] ?? false,
                  onExpansionChanged: (expanded) {
                     setState(() {
                       _expandedFields[currentSubjectName]![fieldName] = expanded;
                     });
                  },
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('「$fieldName」の理解度'),
                          Slider(
                            value: (_fieldComprehensions[currentSubjectName]![fieldName] ?? 1).toDouble(),
                            min: 1,
                            max: 5,
                            divisions: 4,
                            label: (_fieldComprehensions[currentSubjectName]![fieldName] ?? 1).toString(),
                            onChanged: (double value) {
                              setState(() {
                                _fieldComprehensions[currentSubjectName]![fieldName] = value.toInt();
                              });
                            },
                          ),
                          TextFormField(
                            controller: _fieldCommentControllers[currentSubjectName]![fieldName],
                            decoration: InputDecoration(
                              labelText: '「$fieldName」のコメント (任意)',
                              border: const OutlineInputBorder(),
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
} 