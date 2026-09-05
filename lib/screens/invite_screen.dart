import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class InviteScreen extends StatefulWidget {
  final String token;
  final String? refUsername;
  const InviteScreen({super.key, required this.token, this.refUsername});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  bool _isLoading = true;
  bool _isValid = false;
  String _errorMessage = '';
  Map<String, dynamic>? _inviteData;
  bool _isAccepting = false;

  @override
  void initState() {
    super.initState();
    _validateToken();
  }

  Future<void> _validateToken() async {
    final result = await ApiService.validateTokenInvite(widget.token);
    if (!mounted) return;

    if (result.error != null) {
      setState(() {
        _isLoading = false;
        _isValid = false;
        _errorMessage = result.error!;
      });
    } else {
      setState(() {
        _isLoading = false;
        _isValid = true;
        _inviteData = result.data;
      });
    }
  }

  Future<void> _acceptInvite() async {
    setState(() => _isAccepting = true);
    final result = await ApiService.acceptTokenInvite(widget.token, refUsername: widget.refUsername);
    
    if (!mounted) return;
    
    if (result.error != null) {
      setState(() => _isAccepting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error!, style: const TextStyle(color: AppColors.accent)), 
          backgroundColor: AppColors.dark,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height - 150, left: 16, right: 16),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.data?['message'] ?? 'Invite accepted!', style: const TextStyle(color: AppColors.dark)),
          backgroundColor: AppColors.accent,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height - 150, left: 16, right: 16),
        ),
      );
      // Navigate to group or home
      if (result.data != null && result.data!['group_id'] != null) {
        // Here we could pop and push the group detail, or just go to home and let the user navigate
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group Invitation')),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : _isValid
                ? _buildValidInvite()
                : _buildInvalidInvite(),
      ),
    );
  }

  Widget _buildValidInvite() {
    final groupName = _inviteData?['group_name'] ?? 'a group';
    final invitedBy = _inviteData?['invited_by'] ?? 'Someone';

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.group_add, size: 80, color: Colors.blue),
          const SizedBox(height: 24),
          Text(
            "You're invited!",
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            "$invitedBy has invited you to join the group \"$groupName\".",
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (_isAccepting)
            const CircularProgressIndicator()
          else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _acceptInvite,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Accept Invitation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Reject / Cancel', style: TextStyle(color: Colors.grey)),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildInvalidInvite() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 80, color: Colors.red),
          const SizedBox(height: 24),
          Text(
            "Oops!",
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }
}
