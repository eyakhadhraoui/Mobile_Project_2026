import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';

class AccountAdminScreen extends StatefulWidget {
  const AccountAdminScreen({super.key});

  @override
  State<AccountAdminScreen> createState() => _AccountAdminScreenState();
}

class _AccountAdminScreenState extends State<AccountAdminScreen> {
  late Future<List<UserModel>> _users;

  @override
  void initState() {
    super.initState();
    _users = context.read<AuthProvider>().getUsersForAdministration();
  }

  void _reload() => setState(() => _users = context.read<AuthProvider>().getUsersForAdministration());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Gestion des comptes')),
    body: FutureBuilder<List<UserModel>>(
      future: _users,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Erreur : ${snapshot.error}'));
        final users = snapshot.data ?? [];
        if (users.isEmpty) return const Center(child: Text('Aucun compte enregistré.'));
        return ListView.separated(
          padding: const EdgeInsets.all(16), itemCount: users.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final user = users[index];
            return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${user.prenom} ${user.nom}'.trim(), style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(user.email),
              const SizedBox(height: 6),
              Text('E-mail : ${user.emailVerified ? 'vérifié' : 'non vérifié'} · Compte : ${_status(user.accountStatus)}'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                if (user.accountStatus != AccountStatus.approved)
                  OutlinedButton.icon(onPressed: () => _change(user, AccountStatus.approved), icon: const Icon(Icons.check), label: const Text('Valider')),
                if (user.accountStatus != AccountStatus.blocked)
                  OutlinedButton.icon(onPressed: () => _change(user, AccountStatus.blocked), icon: const Icon(Icons.block), label: const Text('Bloquer')),
                if (user.accountStatus != AccountStatus.pending)
                  TextButton(onPressed: () => _change(user, AccountStatus.pending), child: const Text('Remettre en attente')),
              ]),
            ])));
          },
        );
      },
    ),
  );

  Future<void> _change(UserModel user, AccountStatus status) async {
    await context.read<AuthProvider>().setAccountStatus(user.id, status);
    if (mounted) _reload();
  }

  String _status(AccountStatus status) => switch (status) {
    AccountStatus.pending => 'en attente', AccountStatus.approved => 'validé', AccountStatus.blocked => 'bloqué',
  };
}
