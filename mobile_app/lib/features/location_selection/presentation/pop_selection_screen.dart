import 'package:flutter/material.dart';

import '../../pm_visit/presentation/pm_visit_screen.dart';
import '../domain/entities/block.dart';
import '../domain/entities/district.dart';
import '../domain/entities/gp.dart';
import '../domain/entities/pop_summary.dart';
import 'pop_selection_controller.dart';

/// Lets the engineer pick District → Block → GP → POP and view the
/// selected POP's basic details.
///
/// Deliberately shows no map/coordinates/geofence status: the official
/// POP latitude/longitude master data has not been supplied yet (see
/// PopDetail), and no fake coordinates are used. GPS capture and
/// geofence validation belong to the later PM visit/photo module.
class PopSelectionScreen extends StatefulWidget {
  const PopSelectionScreen({super.key});

  @override
  State<PopSelectionScreen> createState() => _PopSelectionScreenState();
}

class _PopSelectionScreenState extends State<PopSelectionScreen> {
  late final PopSelectionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PopSelectionController();
    _controller.addListener(_onChanged);
    _controller.loadDistricts();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Select POP')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_controller.errorMessage != null) ...[
              Text(
                _controller.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
            ],
            _buildDistrictDropdown(),
            const SizedBox(height: 16),
            _buildBlockDropdown(),
            const SizedBox(height: 16),
            _buildGpDropdown(),
            const SizedBox(height: 16),
            _buildPopDropdown(),
            const SizedBox(height: 24),
            _buildPopDetailCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildDistrictDropdown() {
    final isLoading = _controller.districtsStatus == LoadStatus.loading;
    return DropdownButtonFormField<District>(
      decoration: InputDecoration(
        labelText: 'District',
        border: const OutlineInputBorder(),
        suffixIcon: isLoading ? const _InlineSpinner() : null,
      ),
      initialValue: _controller.selectedDistrict,
      items: _controller.districts
          .map((d) => DropdownMenuItem(value: d, child: Text(d.name)))
          .toList(),
      onChanged: isLoading ? null : _controller.selectDistrict,
    );
  }

  Widget _buildBlockDropdown() {
    final isLoading = _controller.blocksStatus == LoadStatus.loading;
    return DropdownButtonFormField<Block>(
      decoration: InputDecoration(
        labelText: 'Block',
        border: const OutlineInputBorder(),
        suffixIcon: isLoading ? const _InlineSpinner() : null,
      ),
      initialValue: _controller.selectedBlock,
      items: _controller.blocks
          .map((b) => DropdownMenuItem(value: b, child: Text(b.name)))
          .toList(),
      onChanged:
          _controller.selectedDistrict == null || isLoading ? null : _controller.selectBlock,
    );
  }

  Widget _buildGpDropdown() {
    final isLoading = _controller.gpsStatus == LoadStatus.loading;
    return DropdownButtonFormField<Gp>(
      decoration: InputDecoration(
        labelText: 'Grama Panchayat (GP)',
        border: const OutlineInputBorder(),
        suffixIcon: isLoading ? const _InlineSpinner() : null,
      ),
      initialValue: _controller.selectedGp,
      items: _controller.gps.map((g) => DropdownMenuItem(value: g, child: Text(g.name))).toList(),
      onChanged: _controller.selectedBlock == null || isLoading ? null : _controller.selectGp,
    );
  }

  Widget _buildPopDropdown() {
    final isLoading = _controller.popsStatus == LoadStatus.loading;
    return DropdownButtonFormField<PopSummary>(
      decoration: InputDecoration(
        labelText: 'POP ID',
        border: const OutlineInputBorder(),
        suffixIcon: isLoading ? const _InlineSpinner() : null,
      ),
      initialValue: _controller.selectedPopSummary,
      items: _controller.pops
          .map(
            (p) => DropdownMenuItem(
              value: p,
              child: Text(p.name == null ? p.popCode : '${p.popCode} — ${p.name}'),
            ),
          )
          .toList(),
      onChanged: _controller.selectedGp == null || isLoading ? null : _controller.selectPop,
    );
  }

  Widget _buildPopDetailCard() {
    if (_controller.popDetailStatus == LoadStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final detail = _controller.selectedPopDetail;
    if (detail == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('POP Details', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _DetailRow(label: 'POP ID', value: detail.popCode),
            if (detail.name != null) _DetailRow(label: 'Name', value: detail.name!),
            _DetailRow(label: 'District', value: detail.districtName),
            _DetailRow(label: 'Block', value: detail.blockName),
            _DetailRow(label: 'GP', value: detail.gpName),
            _DetailRow(label: 'Status', value: detail.isActive ? 'Active' : 'Inactive'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PmVisitScreen(popId: detail.id, popCode: detail.popCode),
                  ),
                );
              },
              child: const Text('Start PM Visit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _InlineSpinner extends StatelessWidget {
  const _InlineSpinner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(12),
      child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
