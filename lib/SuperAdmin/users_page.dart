import 'package:capstone_app/SuperAdmin/superadmin_support.dart';
import 'package:capstone_app/utils/input_safety.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kPrimary = Color(0xFF1E40AF);
const kCardBg = Color(0xFFFFFFFF);
const kSubText = Color(0xFF6B7280);
const kDanger = Color(0xFFDC2626);
const kSuccess = Color(0xFF059669);
const kPageTint = Color(0xFFF8FAFC);

class SuperAdminUsersPage extends StatefulWidget {
  const SuperAdminUsersPage({super.key});

  @override
  State<SuperAdminUsersPage> createState() => _SuperAdminUsersPageState();
}

class _SuperAdminUsersPageState extends State<SuperAdminUsersPage> {
  late Future<List<Map<String, dynamic>>> _usersFuture;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _usersFuture = _fetchUsers();
  }

  Future<List<Map<String, dynamic>>> _fetchUsers() async {
    final body = await superAdminGetJson('/superadmin/users');
    final rawUsers = (body['users'] as List?) ?? const [];
    return rawUsers
        .map((user) => Map<String, dynamic>.from(user as Map))
        .toList();
  }

  Future<void> _refreshUsers() async {
    setState(() {
      _usersFuture = _fetchUsers();
    });
  }

  Future<void> _createUser() async {
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _CreateUserDialog(),
    );

    if (created == null || !mounted) return;
    _showSnack('Created ${created['email']} successfully.');
    await _refreshUsers();
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _EditUserDialog(user: user),
    );
    if (updated == true) {
      await _refreshUsers();
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> user) async {
    final newPassword = await showDialog<String>(
      context: context,
      builder: (context) => _ResetPasswordDialog(
        userName: (user['full_name'] ?? 'User').toString(),
      ),
    );
    if (newPassword == null || newPassword.isEmpty) return;

    final result = await _postAction(
      '/superadmin/reset-user-password',
      {'user_id': user['id'], 'password': newPassword},
      successMessage: 'Password reset for ${user['email']}.',
    );
    if (result) {
      await _refreshUsers();
    }
  }

  Future<void> _toggleDisabled(Map<String, dynamic> user) async {
    final disabled = user['is_disabled'] == true;
    final actionLabel = disabled ? 'reactivate' : 'deactivate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('${disabled ? 'Reactivate' : 'Deactivate'} Account'),
        content: Text(
          'Do you want to $actionLabel ${(user['full_name'] ?? user['email']).toString()}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: disabled ? kSuccess : kDanger,
              foregroundColor: Colors.white,
            ),
            child: Text(disabled ? 'Reactivate' : 'Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await _postAction(
      '/superadmin/set-user-disabled',
      {'user_id': user['id'], 'disabled': !disabled},
      successMessage: disabled
          ? 'Account reactivated successfully.'
          : 'Account deactivated successfully.',
    );
    if (result) {
      await _refreshUsers();
    }
  }

  Future<bool> _postAction(
    String path,
    Map<String, dynamic> payload, {
    required String successMessage,
  }) async {
    try {
      await superAdminPostJson(path, payload);
      _showSnack(successMessage);
      return true;
    } catch (error) {
      _showSnack(error.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final themeBg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF18181B)
        : kPageTint;

    return SuperAdminAccessGuard(
      title: 'Manage Users',
      child: Scaffold(
        backgroundColor: themeBg,
        body: SafeArea(
          child: Column(
            children: [
              _UsersHero(
                onCreatePressed: _createUser,
                searchValue: _search,
                onSearchChanged: (value) =>
                    setState(() => _search = value.trim().toLowerCase()),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _usersFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return _UsersEmptyState(
                        icon: Icons.error_outline_rounded,
                        title: 'Unable to load accounts',
                        message: snapshot.error.toString(),
                        actionLabel: 'Try Again',
                        onAction: _refreshUsers,
                      );
                    }

                    final users = (snapshot.data ?? const [])
                        .where(
                          (user) =>
                              (user['full_name'] ?? '')
                                  .toString()
                                  .toLowerCase()
                                  .contains(_search) ||
                              (user['email'] ?? '')
                                  .toString()
                                  .toLowerCase()
                                  .contains(_search),
                        )
                        .toList();

                    if (users.isEmpty) {
                      return _UsersEmptyState(
                        icon: Icons.people_outline_rounded,
                        title: 'No matching users',
                        message:
                            'Try another search term or create a new account for the organization.',
                        actionLabel: 'Create User',
                        onAction: _createUser,
                      );
                    }

                    final activeCount = users
                        .where((u) => u['is_disabled'] != true)
                        .length;
                    final disabledCount = users
                        .where((u) => u['is_disabled'] == true)
                        .length;

                    return RefreshIndicator(
                      onRefresh: _refreshUsers,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                        children: [
                          _UsersSummaryBar(
                            total: users.length,
                            active: activeCount,
                            disabled: disabledCount,
                          ),
                          const SizedBox(height: 16),
                          ...users.map(
                            (user) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _UserCard(
                                user: user,
                                onEdit: () => _editUser(user),
                                onResetPassword: () => _resetPassword(user),
                                onToggleDisabled: () => _toggleDisabled(user),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsersHero extends StatelessWidget {
  final VoidCallback onCreatePressed;
  final String searchValue;
  final ValueChanged<String> onSearchChanged;

  const _UsersHero({
    required this.onCreatePressed,
    required this.searchValue,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFFE0F2FE)],
          stops: [0, 0.62, 1],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Manage Users',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 10),
          // const Text(
          //   'Create, update, reset, and secure accounts with large controls and clear status labels for easier supervision.',
          //   style: TextStyle(
          //     fontSize: 16,
          //     height: 1.45,
          //     color: Color(0xFFE0ECFF),
          //   ),
          // ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onCreatePressed,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Create New Account'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kPrimary,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: TextField(
              onChanged: onSearchChanged,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Search by name or email',
                hintStyle: const TextStyle(fontSize: 16),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searchValue.isEmpty
                    ? null
                    : const Icon(
                        Icons.check_circle_outline_rounded,
                        color: kSuccess,
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersSummaryBar extends StatelessWidget {
  final int total;
  final int active;
  final int disabled;

  const _UsersSummaryBar({
    required this.total,
    required this.active,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _SummaryChip(label: 'Total', value: '$total', tint: kPrimary),
          _SummaryChip(label: 'Active', value: '$active', tint: kSuccess),
          _SummaryChip(label: 'Disabled', value: '$disabled', tint: kDanger),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color tint;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: tint, fontSize: 14),
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            TextSpan(text: label),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onEdit;
  final VoidCallback onResetPassword;
  final VoidCallback onToggleDisabled;

  const _UserCard({
    required this.user,
    required this.onEdit,
    required this.onResetPassword,
    required this.onToggleDisabled,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = user['is_disabled'] == true;
    final isDeceased = user['is_deceased'] == true;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: kPrimary.withValues(alpha: 0.12),
                child: Text(
                  _initials((user['full_name'] ?? 'U').toString()),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (user['full_name'] ?? 'No Name').toString(),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (user['email'] ?? '').toString(),
                      style: const TextStyle(fontSize: 15, color: kSubText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatusPill(
                label: (user['role'] ?? 'member').toString(),
                color: kPrimary,
              ),
              _StatusPill(
                label: isDisabled ? 'Disabled' : 'Active',
                color: isDisabled ? kDanger : kSuccess,
              ),
              if (isDeceased)
                const _StatusPill(label: 'Deceased', color: kDanger),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ActionButton(
                icon: Icons.edit_outlined,
                label: 'Edit Details',
                onPressed: onEdit,
                color: kPrimary,
              ),
              _ActionButton(
                icon: Icons.lock_reset_rounded,
                label: 'Reset Password',
                onPressed: onResetPassword,
                color: const Color(0xFF7C3AED),
              ),
              _ActionButton(
                icon: isDisabled
                    ? Icons.person_add_alt_1_rounded
                    : Icons.block_rounded,
                label: isDisabled ? 'Reactivate' : 'Deactivate',
                onPressed: onToggleDisabled,
                color: isDisabled ? kSuccess : kDanger,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'U';
    return parts.map((part) => part[0].toUpperCase()).join();
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.22)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _UsersEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  const _UsersEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: kPrimary),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: kSubText,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditUserDialog extends StatefulWidget {
  final Map<String, dynamic> user;

  const _EditUserDialog({required this.user});

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  bool? _isDeceased;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.user['full_name']?.toString() ?? '',
    );
    _emailController = TextEditingController(
      text: widget.user['email']?.toString() ?? '',
    );
    _isDeceased = widget.user['is_deceased'] == true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final fullName = AppInputSecurity.sanitizePlainText(
      _nameController.text,
      maxLength: 120,
    );
    final validation = AppInputSecurity.validateSafeText(
      fullName,
      fieldName: 'Full Name',
      minLength: 2,
      maxLength: 120,
    );
    if (validation != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validation)));
      return;
    }

    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('users')
          .update({'full_name': fullName, 'is_deceased': _isDeceased})
          .eq('id', widget.user['id']);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update user details.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit User Details',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: kPrimary,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Basic profile edits are allowed here. Role and login email are managed through secure SuperAdmin workflows.',
                style: TextStyle(fontSize: 14, height: 1.4, color: kSubText),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _nameController,
                inputFormatters: AppInputSecurity.singleLineFormatters(
                  maxLength: 120,
                ),
                decoration: _dialogInputDecoration(
                  'Full Name',
                  Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _emailController,
                readOnly: true,
                decoration: _dialogInputDecoration(
                  'Email',
                  Icons.email_outlined,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                readOnly: true,
                initialValue: (widget.user['role'] ?? 'member').toString(),
                decoration: _dialogInputDecoration(
                  'Role',
                  Icons.badge_outlined,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _isDeceased ?? false,
                onChanged: (value) => setState(() => _isDeceased = value),
                title: const Text(
                  'Mark as deceased',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Use this only when the user record must reflect death-related status.',
                ),
                activeThumbColor: kDanger,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Saving...' : 'Save Changes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _dialogInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;
  String _role = 'member';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _submitting = true);
    try {
      final body = await superAdminPostJson('/superadmin/create-user', {
        'full_name': AppInputSecurity.sanitizePlainText(
          _nameController.text,
          maxLength: 120,
        ),
        'email': AppInputSecurity.sanitizeEmail(_emailController.text),
        'password': _passwordController.text,
        'role': _role,
      });

      if (!mounted) return;
      Navigator.pop(context, Map<String, dynamic>.from(body['user'] as Map));
    } catch (error) {
      _showError(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create New Account',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: kPrimary,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use simple, clear details so the account owner can sign in without confusion. Officer roles are assigned separately from unit management.',
                  style: TextStyle(fontSize: 14, height: 1.4, color: kSubText),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _nameController,
                  inputFormatters: AppInputSecurity.singleLineFormatters(
                    maxLength: 120,
                  ),
                  decoration: _dialogInputDecoration(
                    'Full Name',
                    Icons.person_outline_rounded,
                  ),
                  validator: (value) => AppInputSecurity.validateSafeText(
                    value,
                    fieldName: 'Full Name',
                    minLength: 2,
                    maxLength: 120,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  inputFormatters: AppInputSecurity.singleLineFormatters(
                    maxLength: 120,
                  ),
                  decoration: _dialogInputDecoration(
                    'Email',
                    Icons.email_outlined,
                  ),
                  validator: AppInputSecurity.validateEmail,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  inputFormatters: AppInputSecurity.singleLineFormatters(
                    maxLength: 72,
                  ),
                  decoration:
                      _dialogInputDecoration(
                        'Temporary Password',
                        Icons.lock_outline_rounded,
                      ).copyWith(
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                  validator: (value) {
                    final raw = value ?? '';
                    if (raw.length < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    if (raw.length > 72) {
                      return 'Password must be 72 characters or less';
                    }
                    if (AppInputSecurity.hasBlockedPayload(raw)) {
                      return 'Password contains invalid content';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: _dialogInputDecoration(
                    'Account Type',
                    Icons.admin_panel_settings_outlined,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'member', child: Text('Member')),
                    DropdownMenuItem(
                      value: 'superadmin',
                      child: Text('SuperAdmin'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _role = value);
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(
                        _submitting ? 'Creating...' : 'Create Account',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dialogInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
    );
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  final String userName;

  const _ResetPasswordDialog({required this.userName});

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reset Password',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: kPrimary,
                fontFamily: 'Montserrat',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Set a new temporary password for ${widget.userName}.',
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: kSubText,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              obscureText: _obscure,
              inputFormatters: AppInputSecurity.singleLineFormatters(
                maxLength: 72,
              ),
              decoration: InputDecoration(
                labelText: 'New Temporary Password',
                prefixIcon: const Icon(Icons.lock_reset_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final raw = _controller.text;
                    if (raw.length < 8 || raw.length > 72) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Password must be 8 to 72 characters long.',
                          ),
                        ),
                      );
                      return;
                    }
                    if (AppInputSecurity.hasBlockedPayload(raw)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Password contains invalid content.'),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(context, raw);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Reset Password'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
