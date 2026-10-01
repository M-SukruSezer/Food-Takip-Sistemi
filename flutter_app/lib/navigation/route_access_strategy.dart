import '../core/nav.dart';
import '../models/user.dart';

abstract interface class RouteAccessStrategy {
  String landingPath(AppUser? user);
  bool canAccess(AppUser? user, String path);
}

/// Menü tanımlarını yetkilendirmenin tek doğruluk kaynağı olarak kullanır.
final class RoleBasedRouteAccessStrategy implements RouteAccessStrategy {
  const RoleBasedRouteAccessStrategy();

  @override
  String landingPath(AppUser? user) => landingPathFor(user);

  @override
  bool canAccess(AppUser? user, String path) =>
      navFor(user).any((item) => item.path == path);
}
