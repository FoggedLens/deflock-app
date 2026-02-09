import 'package:flutter/material.dart';
import '../services/changelog_service.dart';
import '../services/version_service.dart';

class ReleaseNotesScreen extends StatefulWidget {
  const ReleaseNotesScreen({super.key});

  @override
  State<ReleaseNotesScreen> createState() => _ReleaseNotesScreenState();
}

class _ReleaseNotesScreenState extends State<ReleaseNotesScreen> {
  Map<String, String>? _changelogs;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChangelogs();
  }

  Future<void> _loadChangelogs() async {
    try {
      // Ensure changelog service is initialized
      if (!ChangelogService().isInitialized) {
        await ChangelogService().init();
      }
      
      final changelogs = ChangelogService().getAllChangelogs();
      
      if (mounted) {
        setState(() {
          _changelogs = changelogs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ReleaseNotesScreen] Error loading changelogs: $e');
      if (mounted) {
        setState(() {
          _changelogs = {};
          _isLoading = false;
        });
      }
    }
  }

  List<String> _sortVersions(List<String> versions) {
    // Simple version sorting - splits by '.' and compares numerically
    versions.sort((a, b) {
      final aParts = a.split('.').map(int.tryParse).where((v) => v != null).cast<int>().toList();
      final bParts = b.split('.').map(int.tryParse).where((v) => v != null).cast<int>().toList();
      
      // Compare version parts (reverse order for newest first)
      for (int i = 0; i < aParts.length && i < bParts.length; i++) {
        final comparison = bParts[i].compareTo(aParts[i]); // Reverse for desc order
        if (comparison != 0) return comparison;
      }
      
      // If one version has more parts, the longer one is newer
      return bParts.length.compareTo(aParts.length);
    });
    
    return versions;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Release Notes'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _changelogs == null || _changelogs!.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      'No release notes available.',
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    16, 
                    16, 
                    16, 
                    16 + MediaQuery.of(context).padding.bottom,
                  ),
                  children: [
                    // Current version indicator
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Current Version: ${VersionService().version}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Changelog entries
                    ..._buildChangelogEntries(),
                  ],
                ),
    );
  }

  List<Widget> _buildChangelogEntries() {
    if (_changelogs == null || _changelogs!.isEmpty) return [];

    final sortedVersions = _sortVersions(_changelogs!.keys.toList());
    final currentVersion = VersionService().version;

    return sortedVersions.map((version) {
      final content = _changelogs![version]!;
      final isCurrentVersion = version == currentVersion;

      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isCurrentVersion
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                : Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ExpansionTile(
          title: Row(
            children: [
              Text(
                'Version $version',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isCurrentVersion
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              if (isCurrentVersion) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'CURRENT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Text(
                content,
                style: const TextStyle(height: 1.4),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}