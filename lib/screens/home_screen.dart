import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../dev_config.dart';
import '../widgets/map_view.dart';

import '../widgets/add_node_sheet.dart';
import '../widgets/edit_node_sheet.dart';
import '../widgets/camera_provider_with_cache.dart';
import '../widgets/download_area_dialog.dart';
import '../widgets/measured_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<MapViewState> _mapViewKey = GlobalKey<MapViewState>();
  late final AnimatedMapController _mapController;
  bool _editSheetShown = false;
  
  // Track sheet heights for map padding
  double _addSheetHeight = 0.0;
  double _editSheetHeight = 0.0;

  @override
  void initState() {
    super.initState();
    _mapController = AnimatedMapController(vsync: this);
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  String _getFollowMeTooltip(FollowMeMode mode) {
    switch (mode) {
      case FollowMeMode.off:
        return 'Enable follow-me (north up)';
      case FollowMeMode.northUp:
        return 'Enable follow-me (rotating)';
      case FollowMeMode.rotating:
        return 'Disable follow-me';
    }
  }

  IconData _getFollowMeIcon(FollowMeMode mode) {
    switch (mode) {
      case FollowMeMode.off:
        return Icons.gps_off;
      case FollowMeMode.northUp:
        return Icons.gps_fixed;
      case FollowMeMode.rotating:
        return Icons.navigation;
    }
  }

  FollowMeMode _getNextFollowMeMode(FollowMeMode mode) {
    switch (mode) {
      case FollowMeMode.off:
        return FollowMeMode.northUp;
      case FollowMeMode.northUp:
        return FollowMeMode.rotating;
      case FollowMeMode.rotating:
        return FollowMeMode.off;
    }
  }

  void _openAddNodeSheet() {
    final appState = context.read<AppState>();
    // Disable follow-me when adding a camera so the map doesn't jump around
    appState.setFollowMeMode(FollowMeMode.off);
    
    appState.startAddSession();
    final session = appState.session!;          // guaranteed non‑null now

    final controller = _scaffoldKey.currentState!.showBottomSheet(
      (ctx) => MeasuredSheet(
        onHeightChanged: (height) {
          setState(() {
            _addSheetHeight = height;
          });
        },
        child: AddNodeSheet(session: session),
      ),
    );
    
    // Reset height when sheet is dismissed
    controller.closed.then((_) {
      setState(() {
        _addSheetHeight = 0.0;
      });
    });
  }

  void _openEditNodeSheet() {
    final appState = context.read<AppState>();
    // Disable follow-me when editing a camera so the map doesn't jump around
    appState.setFollowMeMode(FollowMeMode.off);
    
    final session = appState.editSession!;     // should be non-null when this is called

    final controller = _scaffoldKey.currentState!.showBottomSheet(
      (ctx) => MeasuredSheet(
        onHeightChanged: (height) {
          setState(() {
            _editSheetHeight = height;
          });
        },
        child: EditNodeSheet(session: session),
      ),
    );
    
    // Reset height when sheet is dismissed
    controller.closed.then((_) {
      setState(() {
        _editSheetHeight = 0.0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // Auto-open edit sheet when edit session starts
    if (appState.editSession != null && !_editSheetShown) {
      _editSheetShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openEditNodeSheet());
    } else if (appState.editSession == null) {
      _editSheetShown = false;
    }

    // Calculate bottom padding for map (90% of active sheet height)
    final activeSheetHeight = _addSheetHeight > 0 ? _addSheetHeight : _editSheetHeight;
    final mapBottomPadding = activeSheetHeight * 0.9;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CameraProviderWithCache>(create: (_) => CameraProviderWithCache()),
      ],
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: const Text('Flock Map'),
          actions: [
            IconButton(
              tooltip: _getFollowMeTooltip(appState.followMeMode),
              icon: Icon(_getFollowMeIcon(appState.followMeMode)),
              onPressed: () {
                final oldMode = appState.followMeMode;
                final newMode = _getNextFollowMeMode(oldMode);
                debugPrint('[HomeScreen] Follow mode changed: $oldMode → $newMode');
                appState.setFollowMeMode(newMode);
                // If enabling follow-me, retry location init in case permission was granted
                if (newMode != FollowMeMode.off) {
                  _mapViewKey.currentState?.retryLocationInit();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.pushNamed(context, '/settings'),
            ),
          ],
        ),
        body: Stack(
          children: [
            MapView(
              key: _mapViewKey,
              controller: _mapController,
              followMeMode: appState.followMeMode,
              bottomPadding: mapBottomPadding,
              onUserGesture: () {
                if (appState.followMeMode != FollowMeMode.off) {
                  appState.setFollowMeMode(FollowMeMode.off);
                }
              },
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + kBottomButtonBarMargin,
                  left: 8,
                  right: 8,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
                  ),
                  margin: EdgeInsets.only(bottom: kBottomButtonBarMargin),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.add_location_alt),
                          label: Text('Tag Node'),
                          onPressed: _openAddNodeSheet,
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size(0, 48),
                            textStyle: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.download_for_offline),
                          label: Text('Download'),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (ctx) => DownloadAreaDialog(controller: _mapController.mapController),
                          ),
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size(0, 48),
                            textStyle: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

