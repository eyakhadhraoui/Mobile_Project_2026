import 'package:flutter/material.dart';

import '../../models/complaint_model.dart';
import 'complaint_detail_screen.dart';

class ComplaintSuccessScreen extends StatelessWidget {
  const ComplaintSuccessScreen({super.key, required this.complaint});
  final ComplaintModel complaint;

  String get reference {
    final suffix = complaint.id.length <= 4
        ? complaint.id.padLeft(4, '0')
        : complaint.id.substring(complaint.id.length - 4);
    return '#REC-${complaint.createdAt.year}-$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Réclamation envoyée'), leading: IconButton(onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst), icon: const Icon(Icons.arrow_back))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Container(width: 118, height: 118, decoration: BoxDecoration(color: const Color(0xFFEAF8EF), borderRadius: BorderRadius.circular(38)), child: const Icon(Icons.check_rounded, color: Color(0xFF35C56A), size: 50)),
                const SizedBox(height: 28),
                const Text('Votre réclamation est envoyée', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: Color(0xFF172B45))),
                const SizedBox(height: 12),
                Text('Référence $reference. Nous vous tiendrons informé de chaque mise à jour.', textAlign: TextAlign.center, style: TextStyle(height: 1.5, color: Colors.blueGrey.shade600)),
                const SizedBox(height: 32),
                Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFDCE7F1))), child: Row(children: [Icon(Icons.notifications_none, color: primary, size: 25), const SizedBox(width: 14), const Expanded(child: Text('Vous recevrez une notification dès qu’il y aura du nouveau.', style: TextStyle(fontSize: 12, color: Color(0xFF647995))))])),
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, height: 56, child: FilledButton(onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => ComplaintDetailScreen(complaint: complaint))), child: const Text('Suivre ma réclamation'))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
