import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/entities/photo_category.dart';
import '../domain/entities/visit_sync_status.dart';
import 'pm_visit_controller.dart';
import 'pm_visit_submission_screen.dart';

/// "Start PM Visit" screen for a selected POP: a checklist of the 5
/// mandatory photo categories. Each is captured with the device camera
/// only (no gallery), GPS-watermarked, and reviewed with Retake/Confirm
/// — the review preview shows the watermarked evidence photo, not the
/// plain original — before counting as Completed.
///
/// Reopening this screen for a POP with an incomplete (draft or
/// in-progress) visit resumes it (see PmVisitController.startVisit)
/// rather than starting a new one, so closing the app mid-capture never
/// loses progress.
///
/// Once all 5 categories are Completed, the visit becomes Ready for
/// Submission automatically (fully offline, no network call), and
/// "Review & Submit" opens [PmVisitSubmissionScreen] — the actual
/// submission/sync action lives there, not on this screen.
class PmVisitScreen extends StatefulWidget {
  const PmVisitScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.popId,
    required this.popCode,
    required this.districtName,
    required this.blockName,
    required this.gpName,
  });

  final String employeeId;
  final String employeeName;
  final int popId;
  final String popCode;
  final String districtName;
  final String blockName;
  final String gpName;

  @override
  State<PmVisitScreen> createState() => _PmVisitScreenState();
}

class _PmVisitScreenState extends State<PmVisitScreen> {
  late final PmVisitController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PmVisitController();
    _controller.addListener(_onChanged);
    _controller.startVisit(
      employeeId: widget.employeeId,
      popId: widget.popId,
      popCode: widget.popCode,
      districtName: widget.districtName,
      blockName: widget.blockName,
      gpName: widget.gpName,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_controller.pendingReview != null) {
      _showReviewSheet();
    }
    setState(() {});
  }

  Future<void> _showReviewSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _PhotoReviewSheet(controller: _controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('PM Visit — ${widget.popCode}')),
      body: !_controller.isStarted
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStatusBanner(),
                const SizedBox(height: 16),
                if (_controller.errorMessage != null) ...[
                  Text(
                    _controller.errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_controller.syncMessage != null) ...[
                  Text(_controller.syncMessage!, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                ],
                ...mandatoryPhotoCategories.map(_buildCategoryTile),
                const SizedBox(height: 24),
                _buildActionButton(),
              ],
            ),
    );
  }

  Widget _buildStatusBanner() {
    final status = _controller.visitStatus;
    if (status == null) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _statusColor(status)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: _statusColor(status)),
          const SizedBox(width: 8),
          Text(
            'Visit status: ${status.label}',
            style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile(PhotoCategory category) {
    final isCompleted = _controller.isCompleted(category);
    final isBusy = _controller.categoryInProgress == category;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isCompleted ? Colors.green : Colors.grey,
        ),
        title: Text(category.label),
        subtitle: Text(isCompleted ? 'Completed' : 'Pending'),
        trailing: ElevatedButton(
          onPressed: isBusy ? null : () => _controller.capturePhoto(category),
          child: isBusy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isCompleted ? 'Retake' : 'Capture Photo'),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    final allDone = _controller.allPhotosValidForSubmission;
    return FilledButton(
      onPressed: !allDone ? null : _openSubmissionScreen,
      child: Text(
        allDone ? 'Review & Submit' : 'Review & Submit (${_controller.photosByCategory.length}/5 completed)',
      ),
    );
  }

  void _openSubmissionScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PmVisitSubmissionScreen(
          controller: _controller,
          employeeName: widget.employeeName,
        ),
      ),
    );
  }

  Color _statusColor(VisitSyncStatus status) {
    switch (status) {
      case VisitSyncStatus.draft:
      case VisitSyncStatus.inProgress:
        return Colors.grey.shade700;
      case VisitSyncStatus.readyForSubmission:
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

class _PhotoReviewSheet extends StatelessWidget {
  const _PhotoReviewSheet({required this.controller});

  final PmVisitController controller;

  @override
  Widget build(BuildContext context) {
    final review = controller.pendingReview;
    if (review == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(review.category.label, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Watermarked evidence photo',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 12),
          // Shows the GPS-watermarked copy (not the plain original) so
          // the engineer can see the exact evidence that will be saved.
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(review.watermarkedFilePath), height: 280, fit: BoxFit.cover),
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Captured at', value: review.capturedAt.toLocal().toString()),
          _InfoRow(label: 'Latitude', value: review.gps.latitude.toStringAsFixed(6)),
          _InfoRow(label: 'Longitude', value: review.gps.longitude.toStringAsFixed(6)),
          _InfoRow(
            label: 'GPS accuracy',
            value: '±${review.gps.accuracyMeters.toStringAsFixed(1)} m',
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    controller.retake();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Retake'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    controller.confirm();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Confirm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
