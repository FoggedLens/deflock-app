import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app_state.dart';
import '../../../services/localization_service.dart';

class MaxNodesSection extends StatefulWidget {
  const MaxNodesSection({super.key});

  @override
  State<MaxNodesSection> createState() => _MaxNodesSectionState();
}

class _MaxNodesSectionState extends State<MaxNodesSection> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final maxNodes = context.read<AppState>().maxNodes;
    _controller = TextEditingController(text: maxNodes.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        final appState = context.watch<AppState>();
        final current = appState.maxNodes;
        final showWarning = current > 1000;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locService.t('settings.maxNodes'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.filter_alt),
              title: Text(locService.t('settings.maxNodesSubtitle')),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showWarning)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: Colors.orange, size: 18),
                          const SizedBox(width: 6),
                          Expanded(child: Text(
                            locService.t('settings.maxNodesWarning'),
                            style: const TextStyle(color: Colors.orange),
                          )),
                        ],
                      ),
                    ),
                ],
              ),
              trailing: SizedBox(
                width: 80,
                child: TextFormField(
                  controller: _controller,
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    border: OutlineInputBorder(),
                  ),
                  onFieldSubmitted: (value) {
                    final n = int.tryParse(value) ?? 10;
                    appState.maxNodes = n;
                    _controller.text = appState.maxNodes.toString();
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
