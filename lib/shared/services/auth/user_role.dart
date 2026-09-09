/// The three roles a Uniflex account can have. One codebase, one running
/// app — which role a person is on decides which shell they see after
/// login, nothing else about the app changes per role.
///
/// Admin absorbs Kitchen Staff duties — there is no separate kitchen login.
enum UserRole {
  student,
  rider,
  admin;

  String get label {
    switch (this) {
      case UserRole.student:
        return 'Student';
      case UserRole.rider:
        return 'Rider';
      case UserRole.admin:
        return 'Admin';
    }
  }
}
