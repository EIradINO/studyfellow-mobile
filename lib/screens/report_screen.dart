import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _postsData = [];
  String? _error;

  // 集計データ
  Map<String, double> _dailyStudyDuration = {};
  Map<String, double> _documentStudyDuration = {};
  double _totalStudyDuration = 0;

  Map<String, String> _documentIdToFileName = {};

  @override
  void initState() {
    super.initState();
    _fetchReportData();
  }

  Future<void> _fetchReportData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _error = 'ユーザーがログインしていません。';
          _isLoading = false;
        });
        return;
      }
      final snapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('user_id', isEqualTo: user.uid)
          .get();
      
      if (snapshot.docs.isEmpty) {
        setState(() {
          _postsData = [];
          _isLoading = false;
        });
        return;
      }

      final posts = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // ドキュメントIDも保持しておく
        return data;
      }).toList();

      // document_id一覧を取得
      final documentIds = posts
          .map((post) => post['document_id'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();
      Map<String, String> docIdToFileName = {};
      if (documentIds.isNotEmpty) {
        final futures = documentIds.map((docId) => FirebaseFirestore.instance
            .collection('document_metadata')
            .doc(docId!)
            .get());
        final metaDocs = await Future.wait(futures);
        for (var metaDoc in metaDocs) {
          if (metaDoc.exists) {
            final data = metaDoc.data() as Map<String, dynamic>?;
            if (data != null && data['file_name'] != null) {
              String fileName = data['file_name'] as String;
              if (fileName.toLowerCase().endsWith('.pdf')) {
                fileName = fileName.substring(0, fileName.length - 4);
              }
              docIdToFileName[metaDoc.id] = fileName;
            }
          }
        }
      }
      _documentIdToFileName = docIdToFileName;

      _processData(posts);

      setState(() {
        _postsData = posts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'データの取得に失敗しました: $e';
        _isLoading = false;
      });
      print('Error fetching report data: $e');
    }
  }

  void _processData(List<Map<String, dynamic>> posts) {
    _dailyStudyDuration.clear();
    _documentStudyDuration.clear();
    _totalStudyDuration = 0;

    for (var post in posts) {
      final duration = (post['duration'] as num?)?.toDouble() ?? 0.0;
      _totalStudyDuration += duration;

      // 日付ごとの集計
      try {
        DateTime createdAt;
        if (post['created_at'] is Timestamp) {
          createdAt = (post['created_at'] as Timestamp).toDate();
        } else if (post['created_at'] is String) {
          String dateStr = post['created_at'].toString().split(' ')[0];
          dateStr = dateStr.replaceAll('年', '-').replaceAll('月', '-').replaceAll('日', '');
          createdAt = DateFormat('yyyy-MM-dd').parse(dateStr);
        } else {
          print("Unknown date format for created_at: \\${post['created_at']}");
          continue;
        }
        final dateKey = DateFormat('yyyy/MM/dd').format(createdAt);
        _dailyStudyDuration[dateKey] = (_dailyStudyDuration[dateKey] ?? 0) + duration;
      } catch (e) {
        print("Error parsing date for daily aggregation: \\${post['created_at']}, error: $e");
      }

      // ドキュメントごとの集計
      String? docLabel;
      final documentId = post['document_id'] as String?;
      if (documentId != null && documentId.isNotEmpty && _documentIdToFileName[documentId] != null) {
        docLabel = _documentIdToFileName[documentId]!;
      } else if (post['document_title'] != null && post['document_title'].toString().isNotEmpty) {
        docLabel = post['document_title'].toString();
      } else if (post['file_name'] != null && post['file_name'].toString().isNotEmpty) {
        docLabel = post['file_name'].toString();
      } else if (documentId != null && documentId.isNotEmpty) {
        docLabel = documentId.length > 15 ? '${documentId.substring(0, 15)}...' : documentId;
      } else if (post['file_urls'] is List && (post['file_urls'] as List).isNotEmpty) {
        try {
          final fileName = Uri.parse((post['file_urls'] as List).first.toString()).pathSegments.last;
          docLabel = fileName.length > 15 ? '${fileName.substring(0, 15)}...' : fileName;
        } catch (e) {
          docLabel = "不明なドキュメント";
        }
      } else {
        docLabel = "その他";
      }
      _documentStudyDuration[docLabel] = (_documentStudyDuration[docLabel] ?? 0) + duration;
    }
    // 日付でソート
    _dailyStudyDuration = Map.fromEntries(
        _dailyStudyDuration.entries.toList()..sort((a, b) => a.key.compareTo(b.key))
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学習レポート'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 16)),
        ),
      );
    }
    if (_postsData.isEmpty) {
      return const Center(child: Text('レポート対象のデータがありません。', style: TextStyle(fontSize: 16)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('総勉強時間: ${(_totalStudyDuration / 60).toStringAsFixed(2)} 時間', 
               style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          
          Text('日別勉強時間 (時間)', style: Theme.of(context).textTheme.titleMedium),
          _buildBarChart(),
          const SizedBox(height: 32),

          Text('ドキュメント別勉強時間 (時間)', style: Theme.of(context).textTheme.titleMedium),
          _buildPieChart(),
          const SizedBox(height: 24),

          // 元データの簡易リスト (デバッグ用や詳細確認用として残すことも可能)
          // Text('学習記録一覧:', style: Theme.of(context).textTheme.titleMedium),
          // _buildRawDataList(),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
    if (_dailyStudyDuration.isEmpty) {
      return const SizedBox(height: 150, child: Center(child: Text('日別データなし')));
    }
    
    final List<BarChartGroupData> barGroups = [];
    int index = 0;
    _dailyStudyDuration.forEach((date, duration) {
      barGroups.add(
        BarChartGroupData(
          x: index++,
          barRods: [
            BarChartRodData(
              toY: duration / 60, // 時間単位で表示
              color: Colors.lightBlue,
              width: 16,
              borderRadius: BorderRadius.circular(4)
            )
          ],
          // showingTooltipIndicators: [0], // 常にツールチップを表示したい場合
        )
      );
    });

    return SizedBox(
      height: 250,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (_dailyStudyDuration.values.reduce((a, b) => a > b ? a : b) / 60) * 1.2, // 最大値の1.2倍をY軸の最大とする
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final date = _dailyStudyDuration.keys.elementAt(group.x);
                return BarTooltipItem(
                  '$date\\n${rod.toY.toStringAsFixed(2)} 時間',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < _dailyStudyDuration.keys.length) {
                     final date = _dailyStudyDuration.keys.elementAt(index);
                     // 日付が長い場合は省略表示 (例: MM/DD)
                     final parts = date.split('/');
                     return SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 4,
                      child: Text(parts.length > 1 ? '${parts[1]}/${parts[2]}' : date, style: const TextStyle(fontSize: 10)),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value % (_totalStudyDuration > 300 ? 1 : 0.5) == 0 && value > 0) { // Y軸のラベルを調整
                    return Text('${value.toStringAsFixed(1)}h', style: const TextStyle(fontSize: 10));
                  }
                  return const Text('');
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _totalStudyDuration > 300 ? 1 : 0.5, // グリッドの間隔（時間）
             getDrawingHorizontalLine: (value) {
                return const FlLine(
                    color: Colors.grey,
                    strokeWidth: 0.5,
                );
            },
          ),
          barGroups: barGroups,
        ),
      ),
    );
  }

  Widget _buildPieChart() {
    if (_documentStudyDuration.isEmpty) {
      return const SizedBox(height: 200, child: Center(child: Text('ドキュメント別データなし')));
    }

    final List<PieChartSectionData> sections = [];
    final List<Color> pieColors = [
      Colors.blue, Colors.red, Colors.green, Colors.orange, Colors.purple, 
      Colors.yellow, Colors.teal, Colors.pink, Colors.indigo, Colors.amber
    ];
    int colorIndex = 0;

    // 割合が小さいものを「その他」としてまとめる閾値 (総時間の5%未満)
    double thresholdPercentage = 5.0; 
    double thresholdDuration = (_totalStudyDuration / 60) * (thresholdPercentage / 100.0);
    
    Map<String, double> displayDocs = {};
    double othersDuration = 0;

    _documentStudyDuration.entries
        .where((entry) => entry.value / 60 > 0.01) // 0.01時間未満は無視
        .toList()
        .sort((a, b) => b.value.compareTo(a.value)); // 降順ソート

    for (var entry in _documentStudyDuration.entries) {
      if (entry.value / 60 < thresholdDuration && _documentStudyDuration.length > 5) { // あまりに項目が多い場合はまとめる
          othersDuration += entry.value;
      } else {
          displayDocs[entry.key] = entry.value;
      }
    }
    if (othersDuration > 0) {
        displayDocs["その他"] = othersDuration;
    }


    displayDocs.forEach((docName, duration) {
      final isTouched = false; // タッチインタラクションは後で追加可能
      final fontSize = isTouched ? 14.0 : 12.0;
      final radius = isTouched ? 90.0 : 80.0;
      final percentage = (duration / _totalStudyDuration) * 100;

      if (percentage < 0.5 && displayDocs.length > 8) return; // あまりに小さいものは表示しない (項目が多い場合)


      sections.add(PieChartSectionData(
        color: pieColors[colorIndex % pieColors.length],
        value: duration / 60, // 時間単位で表示
        title: '${docName.split('/').last}\\n${(duration / 60).toStringAsFixed(2)}h\\n(${percentage.toStringAsFixed(1)}%)',
        radius: radius,
        titleStyle: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: const Color(0xffffffff),
            shadows: const [Shadow(color: Colors.black, blurRadius: 2)]),
        titlePositionPercentageOffset: 0.55,
      ));
      colorIndex++;
    });
    
    if (sections.isEmpty) {
       return const SizedBox(height: 200, child: Center(child: Text('ドキュメント別データなし')));
    }


    return SizedBox(
      height: 300, // 円グラフのサイズを調整
      child: PieChart(
        PieChartData(
          pieTouchData: PieTouchData(
            touchCallback: (FlTouchEvent event, pieTouchResponse) {
              // setState(() { // タッチインタラクションを有効にする場合
              //   if (!event.isInterestedForInteractions ||
              //       pieTouchResponse == null ||
              //       pieTouchResponse.touchedSection == null) {
              //     touchedIndex = -1;
              //     return;
              //   }
              //   touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
              // });
            },
          ),
          borderData: FlBorderData(show: false),
          sectionsSpace: 2, //セクション間のスペース
          centerSpaceRadius: 50, // 中央の空きスペースの半径
          sections: sections,
          startDegreeOffset: -90, // 開始角度 (0時は右、-90時は上から開始)
        ),
      ),
    );
  }

  // (オプション) 元データをリスト表示するウィジェット
  // Widget _buildRawDataList() {
  //   if (_postsData.isEmpty) {
  //     return const Text('データがありません。');
  //   }
  //   return ListView.builder(
  //     shrinkWrap: true,
  //     physics: const NeverScrollableScrollPhysics(),
  //     itemCount: _postsData.length,
  //     itemBuilder: (context, index) {
  //       final post = _postsData[index];
  //       final createdAt = post['created_at'];
  //       String formattedDate = "日付不明";
  //       if (createdAt is Timestamp) {
  //         formattedDate = DateFormat('yyyy/MM/dd HH:mm').format(createdAt.toDate());
  //       } else if (createdAt is String) {
  //         // Firestoreの文字列形式に合わせたパース処理が必要
  //         formattedDate = createdAt; 
  //       }
  //       return Card(
  //         margin: const EdgeInsets.symmetric(vertical: 4),
  //         child: ListTile(
  //           title: Text('内容: ${post['content'] ?? 'N/A'}'),
  //           subtitle: Text('時間: ${post['duration']}秒, 日時: $formattedDate, DocID: ${post['document_id'] ?? 'N/A'}'),
  //           leading: Icon(Icons.bar_chart), // アイコン例
  //         ),
  //       );
  //     },
  //   );
  // }

} 