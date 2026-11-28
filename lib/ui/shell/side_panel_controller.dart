import 'package:flutter/foundation.dart';

import '../settings/settings_store.dart';

/// Active tab displayed inside the docked side panel.
enum SidePanelTab {
  /// Playback queue view.
  queue,

  /// Synchronized or plain lyrics view.
  lyrics,
}

/// Manages open/closed state, active tab, persistence, and responsive auto-hide
/// for the docked right side panel in [AppShell].
class SidePanelController extends ChangeNotifier {
  /// Computes the responsive docked side panel width in logical pixels for a
  /// given [windowWidth], clamping 22% of the window width to `[280.0, 320.0]`.
  static double panelWidthFor(double windowWidth) =>
      (windowWidth * 0.22).clamp(280.0, 320.0);

  /// Minimum window width below which the side panel auto-hides temporarily
  /// without mutating the saved preference.
  static const double kAutoHideWidthThreshold = 1000.0;

  final SettingsStore? _settingsStore;
  bool _isOpen;
  SidePanelTab _activeTab;
  bool _syncing = false;

  /// Creates a [SidePanelController].
  SidePanelController({
    SettingsStore? settingsStore,
    bool initialOpen = false,
    SidePanelTab initialTab = SidePanelTab.queue,
  })  : _settingsStore = settingsStore,
        _isOpen = settingsStore?.settings.sidePanelOpen ?? initialOpen,
        _activeTab = settingsStore != null
            ? tabFromName(settingsStore.settings.sidePanelTab)
            : initialTab {
    _settingsStore?.addListener(_onSettingsChanged);
  }

  /// Saved preference indicating whether the side panel is open.
  bool get isOpen => _isOpen;

  /// Currently selected tab (`queue` or `lyrics`).
  SidePanelTab get activeTab => _activeTab;

  /// Effective visibility for [windowWidth], hiding cleanly when narrower
  /// than [kAutoHideWidthThreshold] without changing [isOpen].
  bool isVisibleForWidth(double windowWidth) =>
      _isOpen && windowWidth >= kAutoHideWidthThreshold;

  /// Converts a persisted tab string to [SidePanelTab], defaulting to `queue`.
  static SidePanelTab tabFromName(String? name) =>
      name == 'lyrics' ? SidePanelTab.lyrics : SidePanelTab.queue;

  /// Converts a [SidePanelTab] to its persisted string key.
  static String tabToName(SidePanelTab tab) =>
      tab == SidePanelTab.lyrics ? 'lyrics' : 'queue';

  /// Opens the side panel, optionally switching to [tab].
  void open({SidePanelTab? tab}) {
    final nextTab = tab ?? _activeTab;
    if (_isOpen && _activeTab == nextTab) return;
    _isOpen = true;
    _activeTab = nextTab;
    _persist();
    notifyListeners();
  }

  /// Closes the side panel without altering the remembered tab.
  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    _persist();
    notifyListeners();
  }

  /// Switches the active tab without opening or closing the panel.
  void setTab(SidePanelTab tab) {
    if (_activeTab == tab) return;
    _activeTab = tab;
    _persist();
    notifyListeners();
  }

  /// Toggles the side panel for [tab]: closes if already open on [tab],
  /// otherwise opens (or switches) to [tab].
  void toggleTab(SidePanelTab tab) {
    if (_isOpen && _activeTab == tab) {
      close();
      return;
    }
    _isOpen = true;
    _activeTab = tab;
    _persist();
    notifyListeners();
  }

  void _persist() {
    final store = _settingsStore;
    if (store == null) return;
    _syncing = true;
    try {
      store.update(
        (s) => s.copyWith(
          sidePanelOpen: _isOpen,
          sidePanelTab: tabToName(_activeTab),
        ),
      );
    } finally {
      _syncing = false;
    }
  }

  void _onSettingsChanged() {
    if (_syncing) return;
    final store = _settingsStore;
    if (store == null) return;
    final nextOpen = store.settings.sidePanelOpen;
    final nextTab = tabFromName(store.settings.sidePanelTab);
    if (nextOpen != _isOpen || nextTab != _activeTab) {
      _isOpen = nextOpen;
      _activeTab = nextTab;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _settingsStore?.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
