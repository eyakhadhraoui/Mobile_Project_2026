import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/complaint_model.dart';
import '../services/complaint_service.dart';

class ComplaintProvider extends ChangeNotifier {
  ComplaintProvider({ComplaintService? service})
    : _service = service ?? ComplaintService();

  final ComplaintService _service;
  StreamSubscription<List<ComplaintModel>>? _subscription;
  List<ComplaintModel> _complaints = const [];
  bool _isLoading = false;
  String? _error;

  List<ComplaintModel> get complaints => _complaints;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void watch(String userId) {
    _watch(_service.watchForUser(userId));
  }

  void watchAll() {
    _watch(_service.watchAll());
  }

  void _watch(Stream<List<ComplaintModel>> source) {
    _subscription?.cancel();
    _complaints = const [];
    _isLoading = true;
    notifyListeners();
    _subscription = source.listen(
      (complaints) {
        _complaints = complaints;
        _isLoading = false;
        _error = null;
        notifyListeners();
      },
      onError: (Object error) {
        _error = error.toString();
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> create(ComplaintModel complaint) => _service.create(complaint);

  Future<ComplaintModel?> complaintById(String id) => _service.getById(id);

  Future<void> update(ComplaintModel complaint) => _service.update(complaint);

  Future<void> updateStatus(String complaintId, ComplaintStatus status) =>
      _service.updateStatus(complaintId, status);

  Future<void> delete(String complaintId, {required String userId}) =>
      _service.delete(complaintId, userId: userId);

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
