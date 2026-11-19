import 'package:flutter/material.dart';

import '../domain/entities/pop_visit_entry.dart';
import 'dashboard_controller.dart';
import 'dashboard_screen.dart' show categoryLabel;
import 'pop_visit_history_controller.dart';

/// POP-wise visit history/status: this POP's District/Block/GP
/// context (from the existing, unchanged `/locations/pops/{id}`
/// endpoint) plus every synced visit, most recent first, each with
/// its compliance status and full category breakdown.
class PopVisitHistoryScreen extends StatefulWidget {
  const PopVisitHistoryScreen({super.key, required this.popId});

  final int popId;

  @override
  State<PopVisitHistoryScreen> createState() => _PopVisitHistoryScreenState();
}

class _PopVisitHistoryScreenState extends State<PopVisitHistoryScreen> {
  late final PopVisitHistoryController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PopVisitHistoryController();
    _controller.addListener(_onChanged);
    _controller.load(widget.popId);
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
    final detail = _controller.popDetail;
    return Scaffold(
      appBar: AppBar(title: Text(detail == null ? 'POP Visit History' : detail.popCode)),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_controller.status == DashboardLoadStatus.loading && _controller.popDetail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.errorMessage != null && _controller.popDetail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _controller.errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    final detail = _controller.popDetail;
    if (detail == null) {
      return const SizedBox.shrink();
    }

    return RefreshIndicator(
      onRefresh: () => _controller.load(widget.popId),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.name == null ? detail.popCode : '${detail.popCode} — ${detail.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text('${detail.districtName} › ${detail.blockName} › ${detail.gpName}'),
                  const SizedBox(height: 6),
                  Text(
                    detail.isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      color: detail.isActive ? Colors.green.shade700 : Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Visit History', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_controller.visits.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No visits recorded yet for this POP.'),
              ),
            ),
          ..._controller.visits.map((visit) => _VisitCard(visit: visit)),
        ],
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.visit});

  final PopVisitEntry visit;

  @override
  Widget build(BuildContext context) {
    final color = visit.isCompliant ? Colors.green.shade700 : Colors.orange.shade800;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  visit.isCompliant ? Icons.check_circle : Icons.error_outline,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Visit date: ${visit.visitDate}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    visit.isCompliant ? 'Compliant' : 'Incomplete',
                    style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Engineer: ${visit.employeeName} (${visit.employeeId})'),
            const SizedBox(height: 4),
            Text('Photos synced: ${visit.photoCount}/5'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...visit.categoriesPresent.map(
                  (category) => _CategoryChip(label: categoryLabel(category), present: true),
                ),
                ...visit.categoriesMissing.map(
                  (category) => _CategoryChip(label: categoryLabel(category), present: false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Synced: ${visit.firstSyncedAt.toLocal()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.present});

  final String label;
  final bool present;

  @override
  Widget build(BuildContext context) {
    final color = present ? Colors.green.shade700 : Colors.grey.shade600;
    return Chip(
      avatar: Icon(present ? Icons.check : Icons.close, size: 16, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      backgroundColor: color.withValues(alpha: 0.1),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }
}
