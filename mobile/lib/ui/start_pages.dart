import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../data/snapshot.dart';
import '../sync/api.dart';
import 'sync_status.dart';
import 'widgets.dart';

/// Aktivasi HP dengan kode dari dashboard (PRD K-01). Butuh internet satu kali.
class ActivationPage extends StatefulWidget {
  const ActivationPage(this.state, {super.key});

  final AppState state;

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage> {
  final _code = TextEditingController();
  var _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await widget.state.activate(_code.text);
    } on ApiError catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Tidak bisa terhubung ke server. Periksa internet lalu coba lagi.';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Aktivasi HP kasir')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Minta kode aktivasi ke owner (menu Device di dashboard). Kode berlaku 15 menit, '
              'hanya bisa dipakai sekali, dan aktivasi butuh internet.'),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            maxLength: 8,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, letterSpacing: 6),
            decoration: InputDecoration(labelText: 'Kode aktivasi', errorText: _error),
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Menghubungi server…' : 'Aktifkan', style: const TextStyle(fontSize: 20)),
          ),
        ]),
      );
}

/// Sudah diaktivasi tetapi data menu belum terunduh, atau device sudah dicabut owner.
class DownloadPage extends StatelessWidget {
  const DownloadPage(this.state, {super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(state.revoked ? 'Device ini sudah dicabut owner.' : 'Data menu belum terunduh. Pastikan ada internet.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (state.revoked)
                FilledButton(onPressed: state.resetDevice, child: const Text('Reset & aktivasi ulang'))
              else
                FilledButton(onPressed: state.syncNow, child: const Text('Coba lagi')),
            ]),
          ),
        ),
      );
}

/// Pilih nama staf lalu masukkan PIN (PRD K-02). Bisa offline.
class LoginPage extends StatelessWidget {
  const LoginPage(this.state, {super.key});

  final AppState state;

  Future<void> _login(BuildContext context, Staff staff) async {
    final pin = await askPin(context, 'PIN ${staff.name}');
    if (pin == null) return;
    final error = await state.login(staff, pin);
    if (error != null && context.mounted) snack(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final snap = state.snapshot!;
    return Scaffold(
      appBar: AppBar(title: Text('${snap.outlet.name} · siapa yang jaga?')),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.2,
        children: [
          for (final s in snap.staff)
            FilledButton.tonal(
              onPressed: () => _login(context, s),
              child: Text(s.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20)),
            ),
        ],
      ),
    );
  }
}

/// Buka shift dengan modal awal (PRD K-03). Reset device juga ada di sini, karena hanya boleh tanpa shift terbuka.
class OpenShiftPage extends StatefulWidget {
  const OpenShiftPage(this.state, {super.key});

  final AppState state;

  @override
  State<OpenShiftPage> createState() => _OpenShiftPageState();
}

class _OpenShiftPageState extends State<OpenShiftPage> {
  final _cash = TextEditingController();
  var _busy = false;

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      await widget.state.openShift(parseMoney(_cash.text)); // app.dart lalu menampilkan layar jualan
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final state = widget.state;
    if (state.pending > 0 && !state.revoked) {
      snack(context, 'Masih ada ${state.pending} data belum terkirim. Sync dulu sebelum reset.');
      return;
    }
    final ok = await confirm(
        context,
        'Reset device?',
        state.revoked
            ? 'Device sudah dicabut. ${state.pending} data yang belum terkirim akan hilang.'
            : 'Semua data di HP ini dihapus dan HP harus diaktivasi ulang dengan kode baru.');
    if (ok) await state.resetDevice();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      appBar: AppBar(title: Text('Halo, ${state.staff!.name}'), actions: [
        TextButton(onPressed: state.logout, child: const Text('Ganti staf')),
        PopupMenuButton<String>(
          onSelected: (_) => _reset(),
          itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('Reset device'))],
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        if (state.needsUpdate)
          const Card(
            child: ListTile(
              leading: Icon(Icons.system_update),
              title: Text('Versi aplikasi terlalu lama'),
              subtitle: Text('Update aplikasi dulu sebelum membuka shift baru.'),
            ),
          ),
        Text('Outlet: ${state.snapshot!.outlet.name}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Hitung uang modal di laci/kantong, lalu buka shift.'),
        const SizedBox(height: 16),
        // Tanpa autofocus: halaman ini juga dibangun di belakang rekap tutup shift, dan keyboard tidak boleh muncul di sana.
        MoneyField(controller: _cash, label: 'Modal awal'),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: _busy || state.needsUpdate ? null : _open,
          child: const Text('Buka shift', style: TextStyle(fontSize: 20)),
        ),
      ]),
      bottomNavigationBar: SafeArea(child: SyncStatusBar(state)),
    );
  }
}
