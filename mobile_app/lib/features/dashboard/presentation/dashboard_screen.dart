import 'package:flutter/material.dart';

import '../../pm_visit/domain/entities/photo_category.dart';
import '../domain/entities/district_compliance.dart';
import '../domain/entities/engineer_performance.dart';
import '../domain/entities/pop_period_status.dart';
import 'dashboard_controller.dart';
import 'pop_visit_history_screen.dart';

/// Compliance dashboard: District-wise and Engineer-wise summaries for
/// a selected fortnight, with a per-POP completed/pending + category
/// breakdown drill-down under each district. Reads only the existing,
/// already-implemented `/api/v1/dashboard/*` endpoints — no mock data,
/// and the same JWT session as every other screen (see
/// core/network/auth_session.dart) is reused automatically.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DashboardController();
    _controller.addListener(_onChanged);
    _controller.loadAll();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Compliance Dashboard'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Districts'),
              Tab(text: 'Engineers'),
            ],
          ),
        ),
        body: Column(
          children: [
            _FortnightSelector(controller: _controller),
            if (_controller.errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _controller.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _DistrictsTab(controller: _controller),
                  _EngineersTab(controller: _controller),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FortnightSelector extends StatelessWidget {
  const _FortnightSelector({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final start = controller.periodStart;
    final end = controller.periodEnd;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous fortnight',
            onPressed: controller.isLoading ? null : controller.goToPreviousFortnight,
          ),
          Expanded(
            child: Center(
              child: start == null || end == null
                  ? const Text('Loading…')
                  : Text(
                      '${_formatDate(start)} – ${_formatDate(end)}',
                      style: Theme.of(context).textTheme.titleSmall,
                      textAlign: TextAlign.center,
                    ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next fortnight',
            onPressed: controller.isLoading ? null : controller.goToNextFortnight,
          ),
          if (!controller.isShowingToday)
            IconButton(
              icon: const Icon(Icons.today),
              tooltip: 'Jump to today',
              onPressed: controller.isLoading ? null : controller.goToToday,
            ),
        ],
      ),
    );
  }
}

class _DistrictsTab extends StatelessWidget {
  const _DistrictsTab({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.districtStatus == DashboardLoadStatus.loading &&
        controller.districtDashboard == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final dashboard = controller.districtDashboard;
    if (dashboard == null) {
      return const SizedBox.shrink();
    }

    return RefreshIndicator(
      onRefresh: controller.loadDistricts,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _OverallSummaryCard(districts: dashboard.districts),
          const SizedBox(height: 8),
          if (dashboard.districts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No districts found.')),
            ),
          ...dashboard.districts.map((district) => _DistrictCard(district: district)),
        ],
      ),
    );
  }
}

class _OverallSummaryCard extends StatelessWidget {
  const _OverallSummaryCard({required this.districts});

  final List<DistrictCompliance> districts;

  @override
  Widget build(BuildContext context) {
    final totalPops = districts.fold<int>(0, (sum, d) => sum + d.totalActivePops);
    final compliantPops = districts.fold<int>(0, (sum, d) => sum + d.compliantPops);
    final completedPops = districts.fold<int>(0, (sum, d) => sum + d.completedPops);
    final pendingPops = districts.fold<int>(0, (sum, d) => sum + d.pendingPops);
    final overallPercent = totalPops == 0 ? 0.0 : (compliantPops / totalPops) * 100;

    return Card(
      color: _complianceColor(overallPercent).withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, color: _complianceColor(overallPercent)),
                const SizedBox(width: 8),
                Text('Overall Compliance', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${overallPercent.toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: _complianceColor(overallPercent),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('$compliantPops of $totalPops active POPs fully compliant (5/5 photos)'),
            const SizedBox(height: 4),
            Text('$completedPops visited this fortnight · $pendingPops pending'),
          ],
        ),
      ),
    );
  }
}

class _DistrictCard extends StatelessWidget {
  const _DistrictCard({required this.district});

  final DistrictCompliance district;

  @override
  Widget build(BuildContext context) {
    final color = _complianceColor(district.compliancePercent);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(district.districtName, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          '${district.compliantPops}/${district.totalActivePops} compliant · '
          '${district.completedPops} completed · ${district.pendingPops} pending',
        ),
        trailing: _PercentBadge(percent: district.compliancePercent, color: color),
        children: district.pops.isEmpty
            ? [const Padding(padding: EdgeInsets.all(16), child: Text('No active POPs.'))]
            : district.pops
                  .map((pop) => _PopStatusTile(districtName: district.districtName, pop: pop))
                  .toList(),
      ),
    );
  }
}

class _PopStatusTile extends StatelessWidget {
  const _PopStatusTile({required this.districtName, required this.pop});

  final String districtName;
  final PopPeriodStatus pop;

  @override
  Widget build(BuildContext context) {
    final isPending = pop.status == PopVisitStatus.pending;
    return ListTile(
      leading: Icon(
        isPending
            ? Icons.hourglass_empty
            : (pop.isCompliant ? Icons.check_circle : Icons.error_outline),
        color: isPending
            ? Colors.grey.shade600
            : (pop.isCompliant ? Colors.green.shade700 : Colors.orange.shade800),
      ),
      title: Text(pop.popName == null ? pop.popCode : '${pop.popCode} — ${pop.popName}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isPending
                ? 'Pending — no visit synced this fortnight'
                : (pop.isCompliant
                      ? 'Completed — all 5 categories synced'
                      : 'Completed — ${pop.categoriesPresent.length}/5 categories synced'),
          ),
          if (!isPending && !pop.isCompliant) ...[
            const SizedBox(height: 4),
            Text(
              'Missing: ${pop.categoriesMissing.map(categoryLabel).join(', ')}',
              style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
            ),
          ],
        ],
      ),
      isThreeLine: !isPending && !pop.isCompliant,
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PopVisitHistoryScreen(popId: pop.popId)),
        );
      },
    );
  }
}

class _EngineersTab extends StatelessWidget {
  const _EngineersTab({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.engineerStatus == DashboardLoadStatus.loading &&
        controller.engineerDashboard == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final dashboard = controller.engineerDashboard;
    if (dashboard == null) {
      return const SizedBox.shrink();
    }

    return RefreshIndicator(
      onRefresh: controller.loadEngineers,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (dashboard.engineers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No active engineers found.')),
            ),
          ...dashboard.engineers.map((engineer) => _EngineerCard(engineer: engineer)),
        ],
      ),
    );
  }
}

class _EngineerCard extends StatelessWidget {
  const _EngineerCard({required this.engineer});

  final EngineerPerformance engineer;

  @override
  Widget build(BuildContext context) {
    final percent = engineer.visitsSynced == 0
        ? 0.0
        : (engineer.compliantVisits / engineer.visitsSynced) * 100;
    final color = engineer.visitsSynced == 0 ? Colors.grey.shade600 : _complianceColor(percent);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(Icons.person, color: color),
        ),
        title: Text(engineer.name),
        subtitle: Text(
          '${engineer.employeeId} · ${engineer.visitsSynced} visit'
          '${engineer.visitsSynced == 1 ? '' : 's'} synced this fortnight',
        ),
        trailing: Text(
          '${engineer.compliantVisits}/${engineer.visitsSynced}\ncompliant',
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _PercentBadge extends StatelessWidget {
  const _PercentBadge({required this.percent, required this.color});

  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '${percent.toStringAsFixed(1)}%',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Clear visual thresholds for "Clear overall compliance/status
/// indicators" — purely presentational; the compliance percentage
/// itself is computed entirely by the backend (see
/// backend/app/services/compliance.py), never recomputed here.
Color _complianceColor(double percent) {
  if (percent >= 80) {
    return Colors.green.shade700;
  }
  if (percent >= 40) {
    return Colors.orange.shade800;
  }
  return Colors.red.shade700;
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

/// Human-readable label for a mandatory category storage key (e.g.
/// `pop_rack` -> `POP Rack`) — reuses the existing PhotoCategory
/// mapping (pm_visit feature) rather than defining a second one.
String categoryLabel(String storageKey) => photoCategoryFromStorageKey(storageKey).label;
