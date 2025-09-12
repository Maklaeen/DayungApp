import 'package:flutter/material.dart';
import 'package:capstone_app/pages/deathnoticedetail.dart';

class RecentDeathNotices extends StatelessWidget {
  const RecentDeathNotices({Key? key}) : super(key: key);

  final Map<String, List<Map<String, String>>> _deathNotices = const {
    'February 2025': [
      {'name': 'Sophia Martinez', 'date': 'February 17, 2025'},
      {'name': 'Liam Anderson', 'date': 'February 17, 2025'},
    ],
    'March 2024': [
      {'name': 'Amina Hassan', 'date': 'March 17, 2024'},
      {'name': 'Carlos Eduardo Silva', 'date': 'March 17, 2024'},
    ],
    'June 2023': [
      {'name': 'Mei Ling Chen', 'date': 'June 17, 2023'},
      {'name': 'Ethan Williams', 'date': 'June 17, 2023'},
    ],
  };

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.3);

    final List<Widget> listItems = [];
    _deathNotices.forEach((monthYear, notices) {
      listItems.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            monthYear,
            style: TextStyle(
              fontSize: 22 * textScale,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
      );

      for (var notice in notices) {
        listItems.add(
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              leading: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.indigo,
                child: Icon(Icons.person, size: 32, color: Colors.white),
              ),
              title: Text(
                notice['name']!,
                style: TextStyle(
                  fontSize: 18 * textScale,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  notice['date']!,
                  style: TextStyle(
                    fontSize: 16 * textScale,
                    color: Colors.black54,
                  ),
                ),
              ),
              trailing: Icon(
                Icons.arrow_forward_ios,
                size: 20 * textScale,
                color: Colors.grey,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeathNoticeDetail(
                      name: notice['name']!,
                      date: notice['date']!,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        automaticallyImplyLeading: false,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          'Dayung',
          style: TextStyle(
            fontSize: 24 * textScale,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.notifications_none,
                    size: 36,
                    color: Colors.orange,
                  ),
                  onPressed: () {},
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    child: Text(
                      '1',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12 * textScale,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.blue,
              child: Icon(
                Icons.account_circle,
                size: 36 * textScale,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),

      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => Navigator.pop(context),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.arrow_back,
                      size: 24 * textScale,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Image.asset(
                  'assets/images/candle.png',
                  width: 28 * textScale,
                  height: 28 * textScale,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'In Memory of Our Members',
                    style: TextStyle(
                      fontSize: 20 * textScale,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: listItems,
            ),
          ),
        ],
      ),
    );
  }
}
