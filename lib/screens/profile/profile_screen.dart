import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../models/complaint_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import '../../providers/user_provider.dart';
import '../complaints/complaints_screen.dart';
import '../admin/account_admin_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UserProvider>();
    final complaints = context.watch<ComplaintProvider>().complaints;
    final user = provider.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil'), actions: [IconButton.filledTonal(onPressed: user == null ? null : () => _editProfile(user), icon: const Icon(Icons.settings_outlined), tooltip: 'Paramètres du compte'), const SizedBox(width: 12)]),
      body: provider.isLoading && user == null
          ? const Center(child: CircularProgressIndicator())
          : user == null
              ? Center(child: Text(provider.error ?? 'Profil introuvable.'))
              : ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 28), children: [
                  Container(padding: const EdgeInsets.fromLTRB(18, 20, 18, 18), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFE7F4FF), Color(0xFFF3F9FE)]), borderRadius: BorderRadius.circular(24)), child: Column(children: [
                    GestureDetector(onTap: () => _changePhoto(user), child: Stack(alignment: Alignment.bottomRight, children: [
                      CircleAvatar(radius: 46, backgroundColor: const Color(0xFF8AC7F3), foregroundImage: user.photo == null ? null : FileImage(File(user.photo!)), child: user.photo == null ? Text(_initials(user), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 24)) : null),
                      Container(width: 27, height: 27, decoration: BoxDecoration(color: const Color(0xFF172B45), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 2)), child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 15)),
                    ])),
                    const SizedBox(height: 12),
                    Text('${user.prenom} ${user.nom}'.trim(), style: const TextStyle(fontSize: 20, color: Color(0xFF172B45))),
                    const SizedBox(height: 5),
                    Text(_roleName(user.rolePrincipal), style: const TextStyle(color: Color(0xFF647995), fontSize: 12)),
                    const SizedBox(height: 9),
                    _VerificationBadge(verified: user.emailVerified),
                  ])),
                  const SizedBox(height: 14),
                  Card(child: Row(children: [
                    _Metric(value: '${complaints.length}', label: 'Réclamations'), const _MetricDivider(),
                    _Metric(value: '${complaints.where((item) => item.status == ComplaintStatus.enCours).length}', label: 'En cours'), const _MetricDivider(),
                    _Metric(value: '${complaints.where((item) => item.status == ComplaintStatus.cloturee).length}', label: 'Résolues'),
                  ])),
                  const SizedBox(height: 14),
                  Card(child: Column(children: [
                    _MenuRow(icon: Icons.assignment_outlined, title: 'Mon activité', subtitle: 'Réclamations et demandes', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ComplaintsScreen()))),
                    const Divider(height: 1, indent: 64),
                    _MenuRow(icon: Icons.mail_outline, title: user.email, subtitle: 'Adresse e-mail', onTap: () => _editProfile(user)),
                    const Divider(height: 1, indent: 64),
                    _MenuRow(icon: Icons.phone_outlined, title: user.telephone, subtitle: 'Téléphone', onTap: () => _editProfile(user)),
                    if (user.rolePrincipal == UserRole.administrateur) ...[
                      const Divider(height: 1, indent: 64),
                      _MenuRow(icon: Icons.admin_panel_settings_outlined, title: 'Gestion des comptes', subtitle: 'Valider ou bloquer les comptes de cet appareil', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountAdminScreen()))),
                    ],
                    const Divider(height: 1, indent: 64),
                    SwitchListTile(secondary: const _MenuIcon(icon: Icons.notifications_outlined), title: const Text('Notifications', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)), subtitle: const Text('Préférences de notification', style: TextStyle(fontSize: 10)), value: user.preferences['notificationsEnabled'] as bool? ?? true, onChanged: (enabled) { final preferences = Map<String, dynamic>.from(user.preferences)..['notificationsEnabled'] = enabled; context.read<UserProvider>().save(_copyUser(user, preferences: preferences)); }),
                    const Divider(height: 1, indent: 64),
                    _MenuRow(icon: Icons.help_outline, title: 'Aide et assistance', subtitle: 'Informations sur l’application', onTap: () => showAboutDialog(context: context, applicationName: 'StudentHub', applicationVersion: '1.0.0', children: const [Text('Application locale de gestion des utilisateurs et des réclamations.')])),
                  ])),
                  const SizedBox(height: 18),
                  TextButton.icon(onPressed: () => context.read<AuthProvider>().signOut(), icon: const Icon(Icons.logout, color: Color(0xFFEF6565)), label: const Text('Se déconnecter', style: TextStyle(color: Color(0xFFEF6565)))),
                  TextButton.icon(onPressed: _deleteAccount, icon: const Icon(Icons.delete_outline, color: Color(0xFFEF6565)), label: const Text('Supprimer mon compte et mes réclamations', style: TextStyle(color: Color(0xFFEF6565), fontSize: 12))),
                  const Center(child: Text('StudentHub · Version 1.0.0', style: TextStyle(fontSize: 10, color: Color(0xFF93A5B9)))),
                ]),
    );
  }

  Future<void> _changePhoto(UserModel user) async {
    final selected = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 82);
    if (selected == null) return;
    final directory = await getApplicationDocumentsDirectory();
    final targetDirectory = Directory(p.join(directory.path, 'profile_photos'));
    await targetDirectory.create(recursive: true);
    final target = await File(selected.path).copy(p.join(targetDirectory.path, '${user.id}_${p.basename(selected.path)}'));
    if (mounted) await context.read<UserProvider>().save(_copyUser(user, photo: target.path));
  }

  Future<void> _editProfile(UserModel user) async {
    final name = TextEditingController(text: '${user.prenom} ${user.nom}'.trim());
    final email = TextEditingController(text: user.email);
    final phone = TextEditingController(text: user.telephone);
    final key = GlobalKey<FormState>();
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Paramètres du compte'),
      content: Form(key: key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nom complet'), validator: (value) => value == null || value.trim().isEmpty ? 'Champ obligatoire.' : null),
        TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Adresse e-mail'), validator: (value) => value == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim()) ? 'Adresse e-mail invalide.' : null),
        TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone'), validator: (value) => value == null || value.trim().isEmpty ? 'Champ obligatoire.' : null),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')), FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(dialogContext, true); }, child: const Text('Enregistrer'))],
    ));
    if (saved == true && mounted) {
      final parts = name.text.trim().split(RegExp(r'\s+'));
      final newEmail = email.text.trim();
      await context.read<UserProvider>().save(_copyUser(user, prenom: parts.first, nom: parts.length > 1 ? parts.skip(1).join(' ') : '', email: newEmail, telephone: phone.text.trim(), emailVerified: newEmail.toLowerCase() == user.email.toLowerCase() ? user.emailVerified : false));
    }
    name.dispose(); email.dispose(); phone.dispose();
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Supprimer le compte ?'), content: const Text('Votre profil, vos réclamations et leur historique seront supprimés de cet appareil.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer'))]));
    if (confirmed == true && mounted) await context.read<AuthProvider>().deleteAccount();
  }

  UserModel _copyUser(UserModel user, {String? nom, String? prenom, String? email, String? telephone, String? photo, Map<String, dynamic>? preferences, bool? emailVerified}) => UserModel(id: user.id, nom: nom ?? user.nom, prenom: prenom ?? user.prenom, email: email ?? user.email, telephone: telephone ?? user.telephone, rolePrincipal: user.rolePrincipal, roleSecondaire: user.roleSecondaire, photo: photo ?? user.photo, preferences: preferences ?? user.preferences, emailVerified: emailVerified ?? user.emailVerified, accountStatus: user.accountStatus);
}

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.verified});
  final bool verified;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(color: verified ? const Color(0xFFE7F8EF) : const Color(0xFFFFF4DE), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(verified ? Icons.verified : Icons.mark_email_unread_outlined, size: 15, color: verified ? const Color(0xFF22A765) : const Color(0xFFB7791F)),
      const SizedBox(width: 5),
      Text(verified ? 'Vérifié' : 'E-mail à vérifier', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: verified ? const Color(0xFF16804A) : const Color(0xFF986515))),
    ]),
  );
}

class _MenuIcon extends StatelessWidget {
  const _MenuIcon({required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFEEF6FC), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: Theme.of(context).colorScheme.primary));
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon; final String title; final String subtitle; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(leading: _MenuIcon(icon: icon), title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)), subtitle: Text(subtitle, style: const TextStyle(fontSize: 10)), trailing: const Icon(Icons.chevron_right, color: Color(0xFF91A6BC)), onTap: onTap);
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label}); final String value; final String label;
  @override
  Widget build(BuildContext context) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 13), child: Column(children: [Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Color(0xFF172B45))), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF647995)))])));
}
class _MetricDivider extends StatelessWidget { const _MetricDivider(); @override Widget build(BuildContext context) => Container(height: 50, width: 1, color: const Color(0xFFE5EDF4)); }

String _initials(UserModel user) => '${user.prenom.isNotEmpty ? user.prenom[0] : ''}${user.nom.isNotEmpty ? user.nom[0] : ''}'.toUpperCase();
String _roleName(UserRole role) => switch (role) { UserRole.locataire => 'Étudiant / locataire', UserRole.proprietaire => 'Propriétaire', UserRole.prestataire => 'Prestataire de services', UserRole.administrateur => 'Administrateur' };
