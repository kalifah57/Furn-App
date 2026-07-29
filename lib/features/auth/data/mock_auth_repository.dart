import '../../../core/errors/result.dart';
import '../domain/auth_repository.dart';

/// مصادقة وهمية للـ MVP: دخول مجهول فوري (mock-first — ADR-0001 §7).
/// تُستبدل بـ Firebase Auth لاحقًا دون تغيير المستدعي.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository();

  AppUser? _current;

  @override
  AppUser? get currentUser => _current;

  @override
  Future<Result<AppUser>> signInAnonymously() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _current = AppUser(
      id: 'anon_${DateTime.now().millisecondsSinceEpoch}',
      isAnonymous: true,
      displayName: 'ضيف',
    );
    return Ok(_current!);
  }

  @override
  Future<Result<void>> signOut() async {
    _current = null;
    return const Ok(null);
  }
}
