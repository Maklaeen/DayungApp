import 'package:flutter/material.dart';

void main() {
  runApp(DayungApp());
}

class DayungApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dayung',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: Color(0xFFF6F7FB),
        primaryColor: Color(0xFF1E88E5),
      ),
      home: SecretaryDashboard(),
    );
  }
}

class SecretaryDashboard extends StatefulWidget {
  @override
  _SecretaryDashboardState createState() => _SecretaryDashboardState();
}

class _SecretaryDashboardState extends State<SecretaryDashboard> {
  int _selectedIndex = 0;

  void _onBottomNavTap(int idx) {
    setState(() => _selectedIndex = idx);
  }

  @override
  Widget build(BuildContext context) {
    final Color green1 = Color(0xFF2ECC71);
    final Color green2 = Color(0xFF27AE60);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(72),
        child: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Dayung',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.black87,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Logos',
                        style: TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: ListView(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Maayung buntag, Secretary!',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                ],
              ),
              SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      color: Color(0xFFFFF3E0),
                      title: 'Total Active Members',
                      value: '259',
                      actionText: 'View All',
                      actionOnTap: () {},
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      color: Color(0xFFE8F5E9),
                      title: 'Recent Death Notices',
                      value: 'Inday H. Pedro M.',
                      actionText: 'View All',
                      actionOnTap: () {},
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      color: Color(0xFFE3F2FD),
                      title: 'Pending Payments',
                      value: '₱21,900\nFrom 219 members',
                      actionText: '',
                      actionOnTap: null,
                      centerValue: true,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 1,
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Color(0xFFF1F8E9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.insert_drive_file_outlined,
                          color: Color(0xFF558B2F),
                          size: 30,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Death Certificate Inbox',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'You have 3 new documents waiting for verification',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 15),
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF1E88E5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          elevation: 0,
                        ),
                        child: Text('View'),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: Icon(Icons.notifications, color: Colors.white),
                      label: Text('Notify members to update info'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: green1,
                        padding: EdgeInsets.symmetric(vertical: 14),
                        textStyle: TextStyle(fontWeight: FontWeight.w700),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: Icon(Icons.group, color: Colors.white),
                      label: Text('Assign members to assist at vigil'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: green2,
                        padding: EdgeInsets.symmetric(vertical: 14),
                        textStyle: TextStyle(fontWeight: FontWeight.w700),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {},
                icon: Icon(Icons.summarize, color: Colors.white),
                label: Text('Death Notice'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF1976D2),
                  padding: EdgeInsets.symmetric(vertical: 14),
                  textStyle: TextStyle(fontWeight: FontWeight.w800),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),

              SizedBox(height: 24),
              Text(
                'Recent Death Notices',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12),
              _NoticeListItem(
                name: 'Inday H. Pedro M.',
                subtitle: 'Submitted 2 hours ago',
                iconColor: Color(0xFFEF9A9A),
                onTap: () {},
              ),
              _NoticeListItem(
                name: 'Juan Dela Cruz',
                subtitle: 'Submitted yesterday',
                iconColor: Color(0xFFB39DDB),
                onTap: () {},
              ),
              _NoticeListItem(
                name: 'Maria Santos',
                subtitle: 'Submitted 3 days ago',
                iconColor: Color(0xFF80DEEA),
                onTap: () {},
              ),
              SizedBox(height: 80),
            ],
          ),
        ),
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onBottomNavTap,
        backgroundColor: Colors.white,
        selectedItemColor: Color(0xFF1976D2),
        unselectedItemColor: Colors.black54,
        showUnselectedLabels: true,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Contributions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'Claims',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: Icon(Icons.note_add),
        label: Text('Death Notice'),
        backgroundColor: Color(0xFF1E88E5),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class _StatCard extends StatelessWidget {
  final Color color;
  final String title;
  final String value;
  final String actionText;
  final VoidCallback? actionOnTap;
  final bool centerValue;

  const _StatCard({
    Key? key,
    required this.color,
    required this.title,
    required this.value,
    required this.actionText,
    this.actionOnTap,
    this.centerValue = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Column(
        crossAxisAlignment: centerValue
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 15),
          Text(
            value,
            textAlign: centerValue ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 10),
          if (actionText.isNotEmpty)
            Align(
              alignment: Alignment.bottomRight,
              child: GestureDetector(
                onTap: actionOnTap ?? () {},
                child: Text(
                  actionText,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1976D2),
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoticeListItem extends StatelessWidget {
  final String name;
  final String subtitle;
  final Color iconColor;
  final VoidCallback? onTap;

  const _NoticeListItem({
    Key? key,
    required this.name,
    required this.subtitle,
    required this.iconColor,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.person_outline, color: iconColor),
        ),
        title: Text(name, style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right),
      ),
    );
  }
}
