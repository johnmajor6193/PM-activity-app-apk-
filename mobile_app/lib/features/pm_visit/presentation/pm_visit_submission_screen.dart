import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/entities/pm_photo_record.dart';
import '../domain/entities/photo_category.dart';
import '../domain/entities/visit_sync_status.dart';
import 'pm_visit_controller.dart';

/// Review-and-submit screen for a PM visit whose 5 mandatory photos are
/// all confirmed. Shows the engineer/location summary, the photo
/// checklist with a review thumbnail for each, and the current sync
/// status, with a Submit (or Retry) action.
///
/// Reuses the same [PmVisitController] instance as the "Start PM
/// Visit" checklist screen — nothing here captures a photo or talks to
/// Google Drive directly; "Submit" calls
/// [PmVisitController.submitVisit], which uses the existing, unchanged
/// sync pipeline.
class PmVisitSubmissionScreen extends StatefulWidget {
  const PmVisitSubmissionScreen({
    super.key,
    required this.controller,
    required this.employeeName,
  });

  final PmVisitController controller;
  final String employeeName;

  @override
  State<PmVisitSubmissionScreen> createState() => _PmVisitSubmissionScreenState();
}

class _PmVisitSubmissionScreenState extends State<PmVisitSubmissionScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final visit = controller.visit;

    return Scaffold(
      appBar: AppBar(title: const Text('Review & Submit PM Visit')),
      body: visit == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStatusBanner(visit.status),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Visit Details', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _InfoRow(label: 'Employee', value: '${widget.employeeName} (${visit.employeeId})'),
                        _InfoRow(label: 'District', value: visit.districtName),
                        _InfoRow(label: 'Block', value: visit.blockName),
                        _InfoRow(label: 'GP', value: visit.gpName),
                        _InfoRow(label: 'POP ID', value: visit.popCode),
                        _InfoRow(label: 'Visit Date/Time', value: visit.startedAt.toLocal().toString()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Mandatory Photographs', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...mandatoryPhotoCategories.map(
                  (category) => _buildPhotoChecklistTile(context, controller, category),
                ),
                const SizedBox(height: 16),
                if (controller.errorMessage != null) ...[
                  Text(
                    controller.errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                ],
                if (controller.syncMessage != null) ...[
                  Text(controller.syncMessage!, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 12),
                ],
                _buildSubmitButton(controller, visit.status),
              ],
            ),
    );
  }

  Widget _buildPhotoChecklistTile(
    BuildContext context,
    PmVisitController controller,
    PhotoCategory category,
  ) {
    final photo = controller.photosByCategory[category];
    final isValid = photo != null && photo.isValidForSubmission;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isValid ? Icons.check_circle : Icons.cancel,
          color: isValid ? Colors.green : Colors.red,
        ),
        title: Text(category.label),
        subtitle: Text(isValid ? 'Completed' : 'Missing or invalid'),
        trailing: photo?.watermarkedFilePath == null
            ? null
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(photo!.watermarkedFilePath!),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
        onTap: photo?.watermarkedFilePath == null
            ? null
            : () => _showPhotoPreview(context, category, photo!),
      ),
    );
  }

  Future<void> _showPhotoPreview(BuildContext context, PhotoCategory category, PmPhotoRecord photo) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(category.label, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Image.file(File(photo.watermarkedFilePath!)),
              const SizedBox(height: 12),
              Text('Captured at: ${photo.capturedAt.toLocal()}'),
              Text('Lat: ${photo.gps.latitude.toStringAsFixed(6)}  '
                  'Lng: ${photo.gps.longitude.toStringAsFixed(6)}'),
              Text('GPS accuracy: ±${photo.gps.accuracyMeters.toStringAsFixed(1)} m'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton(PmVisitController controller, VisitSyncStatus status) {
    final isRetry = status == VisitSyncStatus.syncFailed;
    final alreadyDone = status == VisitSyncStatus.submitted;

    if (alreadyDone) {
      return const Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text('This visit has already been submitted.'),
        ],
      );
    }

    return FilledButton(
      onPressed: controller.canSubmit ? () => controller.submitVisit() : null,
      child: controller.isSyncing
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(isRetry ? 'Retry Submission' : 'Submit Visit'),
    );
  }

  Widget _buildStatusBanner(VisitSyncStatus status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Text(
            'Visit status: ${status.label}',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Color _statusColor(VisitSyncStatus status) {
    switch (status) {
      case VisitSyncStatus.draft:
      case VisitSyncStatus.inProgress:
        return Colors.grey.shade700;
      case VisitSyncStatus.readyForSubmission:
        return Colors.orange.shade800;
      case VisitSyncStatus.pendingSync:
        return Colors.orange.shade800;
      case VisitSyncStatus.syncing:
        return Colors.blue.shade700;
      case VisitSyncStatus.synced:
      case VisitSyncStatus.submitted:
        return Colors.green.shade700;
      case VisitSyncStatus.syncFailed:
        return Colors.red.shade700;
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
