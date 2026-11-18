/// Holds the current logged-in employee's JWT access token in memory,
/// so API calls that now require it (see backend/app/api/deps.py) can
/// attach `Authorization: Bearer <token>`.
///
/// Deliberately in-memory only, not persisted to disk — losing it on
/// app restart (requiring a fresh login) is the same behavior as
/// before this existed; nothing about the login flow itself changes.
/// Never logged or printed anywhere.
class AuthSession {
  AuthSession._();

  static final AuthSession instance = AuthSession._();

  String? accessToken;
}
