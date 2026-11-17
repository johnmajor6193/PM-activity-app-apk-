import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/entities/photo_category.dart';
import 'pm_visit_controller.dart';

/// "Start PM Visit" screen for a selected POP: a checklist of the 5
/// mandatory photo categories. Each is captured with the device camera
/// only (no gallery), reviewed with Retake/Confirm, and only counts as
/// Completed once confirmed. Submitting is disabled until all 5 are
/// Completed; this screen does not implement the actual submission
/// workflow (a later module).
class PmVisitScreen extends StatefulWidget {
  const PmVisitScreen({super.key, required this.popId, required this.popCode});

  final int popId;
  final String popCode;

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
    _controller.startVisit(popId: widget.popId, popCode: widget.popCode);
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
                if (_controller.errorMessage != null) ...[
                  Text(
                    _controller.errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 16),
                ],
                ...mandatoryPhotoCategories.map(_buildCategoryTile),
                const SizedBox(height: 24),
                _buildSubmitButton(),
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

  Widget _buildSubmitButton() {
    final allDone = _controller.allPhotosCompleted;
    return FilledButton(
      onPressed: allDone
          ? () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'All 5 photos captured. Submission will be implemented in a later step.',
                  ),
                ),
              );
            }
          : null,
      child: Text(
        allDone
            ? 'Submit PM Visit'
            : 'Submit PM Visit (${_controller.photosByCategory.length}/5 completed)',
      ),
    );
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
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(review.localFilePath), height: 240, fit: BoxFit.cover),
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
