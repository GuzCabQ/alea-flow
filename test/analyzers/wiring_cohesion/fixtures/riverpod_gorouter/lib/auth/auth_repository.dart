// ignore_for_file: uri_does_not_exist
abstract class AuthRepository {
  Future<void> persistToken(String token);
}

class AuthRepositoryImpl implements AuthRepository {
  @override
  Future<void> persistToken(String token) async {}
}
