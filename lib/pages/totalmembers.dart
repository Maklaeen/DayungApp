import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TotalMembersPage extends StatefulWidget {
  const TotalMembersPage({super.key});

  @override
  State<TotalMembersPage> createState() => _TotalMembersPageState();
}

class _TotalMembersPageState extends State<TotalMembersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String> activeMembers = [];
  List<String> pendingMembers = [];
  bool _loading = true;

  // Scroll controllers for each tab
  final ScrollController _activeScrollController = ScrollController();
  final ScrollController _pendingScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchMembers();
  }

  @override
  void dispose() {
    _activeScrollController.dispose();
    _pendingScrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchMembers() async {
    setState(() => _loading = true);
    final supabase = Supabase.instance.client;
    try {
      // Fetch active members (status = 'approved')
      final active = await supabase
          .from('users')
          .select('full_name')
          .eq('status', 'approved')
          .order('full_name', ascending: true);
      // Fetch pending members (status = 'pending')
      final pending = await supabase
          .from('users')
          .select('full_name')
          .eq('status', 'pending')
          .order('full_name', ascending: true);
      setState(() {
        activeMembers = List<String>.from(
          active.map((u) => u['full_name'] ?? 'Unnamed'),
        );
        pendingMembers = List<String>.from(
          pending.map((u) => u['full_name'] ?? 'Unnamed'),
        );
        _loading = false;
      });
    } catch (e) {
      setState(() {
        activeMembers = [];
        pendingMembers = [];
        _loading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading members: $e')));
    }
  }

  Widget _memberTile(String name) {
    return Column(
      children: [
        ListTile(
          leading: const CircleAvatar(
            radius: 26,
            backgroundColor: Colors.transparent,
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 32, color: Colors.blue),
            ),
          ),
          title: Text(
            name,
            style: const TextStyle(
              fontSize: 20,
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        const Divider(thickness: 1, height: 1),
      ],
    );
  }

  void _scrollToLetter(String letter, int tabIndex) {
    final members = tabIndex == 0 ? activeMembers : pendingMembers;
    final controller = tabIndex == 0
        ? _activeScrollController
        : _pendingScrollController;
    final index = members.indexWhere(
      (name) =>
          name.isNotEmpty && name[0].toUpperCase() == letter.toUpperCase(),
    );
    if (index != -1) {
      controller.animateTo(
        index * 72.0, // Approximate height of each tile+divider
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _alphabetScrollbar() {
    return Container(
      width: 32,
      margin: const EdgeInsets.only(right: 4, top: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(26, (i) {
          final letter = String.fromCharCode(65 + i);
          return InkWell(
            onTap: () => _scrollToLetter(letter, _tabController.index),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                letter,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                  fontFamily: 'Montserrat',
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            // AppBar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Dayung",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  Row(
                    children: [
                      Stack(
                        children: [
                          const Icon(
                            Icons.notifications,
                            color: Colors.orange,
                            size: 28,
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 14,
                                minHeight: 14,
                              ),
                              child: const Text(
                                '1',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      const CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.blueGrey,
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(thickness: 1.2),
            // Back and Members title
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    "Members",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ],
              ),
            ),
            // Tabs
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 8, right: 12),
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.black,
                labelColor: Colors.black,
                unselectedLabelColor: Colors.black54,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  fontFamily: 'Montserrat',
                ),
                tabs: const [
                  Tab(text: "Active"),
                  Tab(text: "Pending"),
                ],
              ),
            ),
            const Divider(thickness: 1),
            // List and Alphabet scrollbar
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Members list
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              // Active members
                              ListView.builder(
                                controller: _activeScrollController,
                                padding: EdgeInsets.zero,
                                itemCount: activeMembers.length,
                                itemBuilder: (context, i) =>
                                    _memberTile(activeMembers[i]),
                              ),
                              // Pending members
                              ListView.builder(
                                controller: _pendingScrollController,
                                padding: EdgeInsets.zero,
                                itemCount: pendingMembers.length,
                                itemBuilder: (context, i) =>
                                    _memberTile(pendingMembers[i]),
                              ),
                            ],
                          ),
                        ),
                        // Alphabet scrollbar
                        _alphabetScrollbar(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
