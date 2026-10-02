import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/approvals_screen.dart';
import '../screens/batches_screen.dart';
import '../screens/daily_report_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/logs_screen.dart';
import '../screens/pdks_admin_screen.dart';
import '../screens/pdks_screen.dart';
import '../screens/pin_screen.dart';
import '../screens/petty_cash_screen.dart';
import '../screens/product_types_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/recommendations_screen.dart';
import '../screens/requests_screen.dart';
import '../screens/roster_screen.dart';
import '../screens/sales_screen.dart';
import '../screens/stock_coverage_screen.dart';
import '../screens/stores_screen.dart';
import '../screens/timesheet_screen.dart';
import '../screens/users_screen.dart';

typedef ScreenBuilder = Widget Function(GoRouterState state);

/// Rota bilgisini somut ekran nesnesine dönüştüren tek üretim noktası.
abstract final class AppScreenFactory {
  static final Map<String, ScreenBuilder> builders = {
    '/dashboard': (_) => const DashboardScreen(),
    '/recommendations': (_) => const RecommendationsScreen(),
    '/batches': (state) => BatchesScreen(
      key: ValueKey(state.uri.toString()),
      initialTab: state.uri.queryParameters['tab'],
    ),
    '/roster': (_) => const RosterScreen(),
    '/product-types': (_) => const ProductTypesScreen(),
    '/stores': (_) => const StoresScreen(),
    '/users': (_) => const UsersScreen(),
    '/sales': (state) => SalesScreen(
      key: ValueKey(state.uri.toString()),
      initialRange: state.uri.queryParameters['range'],
      initialKind: state.uri.queryParameters['kind'],
    ),
    '/logs': (_) => const LogsScreen(),
    '/approvals': (_) => const ApprovalsScreen(),
    '/petty-cash': (_) => const PettyCashScreen(),
    '/daily-report': (_) => const DailyReportScreen(),
    '/stock-coverage': (_) => const StockCoverageScreen(),
    '/pdks': (state) => PdksScreen(
      key: ValueKey(state.uri.toString()),
      shiftRequired: state.uri.queryParameters['shift'] == '1',
    ),
    '/pdks-admin': (_) => const PdksAdminScreen(),
    '/requests': (_) => const RequestsScreen(),
    '/pin': (_) => const PinScreen(),
    '/timesheet': (_) => const TimesheetScreen(),
    '/profile': (_) => const ProfileScreen(),
  };
}
