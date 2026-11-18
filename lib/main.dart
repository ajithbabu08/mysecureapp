import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _appLockerChannel = MethodChannel('com.example.mysecureapp/app_locker');

void main() {
  runApp(const AppLockerApp());
}

class AppLockerApp extends StatelessWidget {
  const AppLockerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Locker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF536DFE),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
        useMaterial3: true,
      ),
      home: const AppLockerHomePage(),
    );
  }
}

class _AppInfo {
  const _AppInfo({required this.packageName, required this.name});

  final String packageName;
  final String name;

  factory _AppInfo.fromMap(Map<Object?, Object?> map) {
    return _AppInfo(
      packageName: map['packageName']! as String,
      name: map['name']! as String,
    );
  }
}

class AppLockerHomePage extends StatefulWidget {
  const AppLockerHomePage({super.key});

  @override
  State<AppLockerHomePage> createState() => _AppLockerHomePageState();
}

class _AppLockerHomePageState extends State<AppLockerHomePage>
    with WidgetsBindingObserver {
  List<_AppInfo> _apps = const [];
  Set<String> _lockedPackages = {};
  bool _hasPin = false;
  bool _hasAccessibility = false;
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait<Object?>([
        _appLockerChannel.invokeMethod<List<Object?>>('getApps'),
        _appLockerChannel.invokeMethod<List<Object?>>('getLockedPackages'),
        _appLockerChannel.invokeMethod<bool>('hasPin'),
        _appLockerChannel.invokeMethod<bool>('hasAccessibilityPermission'),
      ]);
      if (!mounted) return;

      setState(() {
        _apps = (results[0]! as List<Object?>)
            .map((item) => _AppInfo.fromMap(item! as Map<Object?, Object?>))
            .toList();
        _lockedPackages = (results[1]! as List<Object?>).cast<String>().toSet();
        _hasPin = results[2]! as bool;
        _hasAccessibility = results[3]! as bool;
        _isLoading = false;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.message ?? 'Could not load app locker settings.';
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'App locking is currently available on Android only.';
      });
    }
  }

  Future<void> _toggleApp(_AppInfo app, bool shouldLock) async {
    if (shouldLock && !_hasPin) {
      final wantsToSetPin = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Set a PIN first'),
          content: const Text('Create a PIN before choosing apps to lock.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Set PIN'),
            ),
          ],
        ),
      );
      if (!mounted || wantsToSetPin != true) return;
      if (!await _showPinSetup()) return;
      if (!_hasPin) return;
    }

    final previousPackages = _lockedPackages;
    final updatedPackages = {..._lockedPackages};
    if (shouldLock) {
      updatedPackages.add(app.packageName);
    } else {
      updatedPackages.remove(app.packageName);
    }

    setState(() => _lockedPackages = updatedPackages);
    try {
      await _appLockerChannel.invokeMethod<void>('setLockedPackages', {
        'packages': updatedPackages.toList(),
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _lockedPackages = previousPackages);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not update app lock.')),
      );
      await _load();
    }
  }

  Future<bool> _showPinSetup() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PinSetupPage(hasExistingPin: _hasPin),
      ),
    );
    if (saved == true) {
      await _load();
    }
    return saved == true;
  }

  Future<void> _openPinSetup() async {
    await _showPinSetup();
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      await _appLockerChannel.invokeMethod<void>('openAccessibilitySettings');
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not open settings.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredApps = _apps
        .where(
          (app) => app.name.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
    final lockIsActive = _hasPin && _hasAccessibility;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'App Locker',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? _ErrorPanel(message: _errorMessage!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  children: [
                    _ProtectionHeader(
                      isActive: lockIsActive && _lockedPackages.isNotEmpty,
                      lockedCount: _lockedPackages.length,
                    ),
                    const SizedBox(height: 20),
                    _SetupCard(
                      hasPin: _hasPin,
                      hasAccessibility: _hasAccessibility,
                      onPinPressed: _openPinSetup,
                      onAccessibilityPressed: _openAccessibilitySettings,
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Text(
                          'Your apps',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Text(
                          '${_lockedPackages.length} locked',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF697386)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        hintText: 'Search installed apps',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (filteredApps.isEmpty)
                      const _EmptyApps()
                    else
                      ...filteredApps.map(
                        (app) => _AppTile(
                          app: app,
                          isLocked: _lockedPackages.contains(app.packageName),
                          onChanged: (value) => _toggleApp(app, value),
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'App monitoring uses Android Accessibility settings to '
                      'notice when a selected app opens. It does not read '
                      'screen content.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: Color(0xFF697386),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ProtectionHeader extends StatelessWidget {
  const _ProtectionHeader({required this.isActive, required this.lockedCount});

  final bool isActive;
  final int lockedCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF283B75), Color(0xFF536DFE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'Protection is on' : 'Set up your protection',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isActive
                      ? '$lockedCount ${lockedCount == 1 ? 'app' : 'apps'} protected'
                      : 'Choose apps and secure them with your PIN.',
                  style: const TextStyle(
                    color: Color(0xFFDCE3FF),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Icon(
            isActive ? Icons.shield_rounded : Icons.shield_outlined,
            color: Colors.white,
            size: 42,
          ),
        ],
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.hasPin,
    required this.hasAccessibility,
    required this.onPinPressed,
    required this.onAccessibilityPressed,
  });

  final bool hasPin;
  final bool hasAccessibility;
  final VoidCallback onPinPressed;
  final VoidCallback onAccessibilityPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Get started',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _SetupStep(
              number: '1',
              title: hasPin ? 'PIN is set' : 'Create a PIN',
              subtitle: hasPin
                  ? 'Your lock screen is protected.'
                  : 'Use a 4-8 digit PIN for protected apps.',
              complete: hasPin,
            ),
            const SizedBox(height: 12),
            _SetupStep(
              number: '2',
              title: hasAccessibility
                  ? 'App monitoring is enabled'
                  : 'Enable app monitoring',
              subtitle: hasAccessibility
                  ? 'Android can detect when a protected app opens.'
                  : 'Turn on App Locker in Android Accessibility settings.',
              complete: hasAccessibility,
            ),
            const SizedBox(height: 16),
            if (!hasPin)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onPinPressed,
                  child: const Text('Create PIN'),
                ),
              )
            else if (!hasAccessibility)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onAccessibilityPressed,
                  child: const Text('Open Accessibility settings'),
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onPinPressed,
                  icon: const Icon(Icons.password),
                  label: const Text('Change PIN'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.complete,
  });

  final String number;
  final String title;
  final String subtitle;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: complete
              ? const Color(0xFFE5F5EC)
              : const Color(0xFFF0F1F6),
          child: complete
              ? const Icon(Icons.check, size: 17, color: Color(0xFF228B54))
              : Text(
                  number,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF697386),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.isLocked,
    required this.onChanged,
  });

  final _AppInfo app;
  final bool isLocked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SwitchListTile(
        value: isLocked,
        onChanged: onChanged,
        secondary: CircleAvatar(
          backgroundColor: const Color(0xFFE9EDFF),
          child: Text(
            app.name.isEmpty ? '?' : app.name[0].toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF3D55D9),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(
          app.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          isLocked ? 'PIN required to open' : 'Not protected',
          style: const TextStyle(fontSize: 12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      ),
    );
  }
}

class _EmptyApps extends StatelessWidget {
  const _EmptyApps();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 38, color: Color(0xFF8A93A6)),
          SizedBox(height: 10),
          Text(
            'No launchable apps found',
            style: TextStyle(color: Color(0xFF697386)),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class PinSetupPage extends StatefulWidget {
  const PinSetupPage({required this.hasExistingPin, super.key});

  final bool hasExistingPin;

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  final _currentPin = TextEditingController();
  final _newPin = TextEditingController();
  final _confirmPin = TextEditingController();
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void dispose() {
    _currentPin.dispose();
    _newPin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newPin = _newPin.text;
    if (!RegExp(r'^\d{4,8}$').hasMatch(newPin)) {
      setState(() => _errorMessage = 'PIN must contain 4 to 8 digits.');
      return;
    }
    if (newPin != _confirmPin.text) {
      setState(() => _errorMessage = 'The PINs do not match.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      if (widget.hasExistingPin) {
        final verification = await _appLockerChannel
            .invokeMapMethod<Object?, Object?>('verifyPin', {
              'pin': _currentPin.text,
            });
        if (verification?['success'] != true) {
          final waitSeconds = verification?['retryAfterSeconds'] as int? ?? 0;
          if (!mounted) return;
          setState(() {
            _isSaving = false;
            _errorMessage = waitSeconds > 0
                ? 'Too many attempts. Try again in $waitSeconds seconds.'
                : 'Current PIN is incorrect.';
          });
          return;
        }
      }

      await _appLockerChannel.invokeMethod<void>('setPin', {'pin': newPin});
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = error.message ?? 'Could not save your PIN.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.hasExistingPin ? 'Change PIN' : 'Create PIN'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.lock_outline, size: 56, color: Color(0xFF536DFE)),
          const SizedBox(height: 16),
          Text(
            widget.hasExistingPin ? 'Choose a new PIN' : 'Secure your apps',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your PIN is stored securely on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF697386)),
          ),
          const SizedBox(height: 28),
          if (widget.hasExistingPin) ...[
            _PinField(controller: _currentPin, label: 'Current PIN'),
            const SizedBox(height: 14),
          ],
          _PinField(controller: _newPin, label: 'New PIN'),
          const SizedBox(height: 14),
          _PinField(controller: _confirmPin, label: 'Confirm new PIN'),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: Text(_isSaving ? 'Saving...' : 'Save PIN'),
          ),
        ],
      ),
    );
  }
}

class _PinField extends StatefulWidget {
  const _PinField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  State<_PinField> createState() => _PinFieldState();
}

class _PinFieldState extends State<_PinField> {
  bool _isHidden = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      keyboardType: TextInputType.number,
      obscureText: _isHidden,
      maxLength: 8,
      decoration: InputDecoration(
        labelText: widget.label,
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        suffixIcon: IconButton(
          tooltip: _isHidden ? 'Show PIN' : 'Hide PIN',
          onPressed: () => setState(() => _isHidden = !_isHidden),
          icon: Icon(_isHidden ? Icons.visibility : Icons.visibility_off),
        ),
      ),
    );
  }
}
