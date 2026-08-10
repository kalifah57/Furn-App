import 'package:equatable/equatable.dart';

import '../../../core/errors/result.dart';

/// مستخدم التطبيق (مجرّد عن مزوّد المصادقة).
class AppUser extends Equatable {
  const AppUser({
    required this.id,
    this.isAnonymous = true,
    this.displayName = '',
  });

  final String id;
  final bool isAnonymous;
  final String displayName;

  @override
  List<Object?> get props => [id, isAnonymous, displayName];
}

/// واجهة المصادقة (architecture.md — Firebase Auth، مؤجّلة خلف تجريد — القرار G6).
abstract interface class AuthRepository {
  AppUser? get currentUser;
  Future<Result<AppUser>> signInAnonymously();
  Future<Result<void>> signOut();
}
