import 'package:flutter/material.dart';
import '../widgets/app_shell.dart';

import 'admin_organizations_screen.dart';
import 'admin_users_screen.dart';
import 'admin_database_viewer.dart';

/// Platform console for system administrators (tenants, users, raw data).
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: ShellMenuButton.maybe(context),
          title: const Text('System Admin'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.business_outlined, size: 18), text: 'Organizations'),
              Tab(icon: Icon(Icons.manage_accounts_outlined, size: 18), text: 'Users'),
              Tab(icon: Icon(Icons.storage_outlined, size: 18), text: 'Data explorer'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminOrganizationsScreen(),
            AdminUsersScreen(),
            AdminDatabaseViewer(),
          ],
        ),
      ),
    );
  }
}
