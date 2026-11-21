import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../core/format.dart';
import '../data/store.dart';
import 'theme.dart';
import 'widgets.dart';

const _offlineBg = Color(0xFFFEF3C7); // amber-100
const _offlineFg = Color(0xFF78350F); // amber-900, kontras 8:1 di atas amber-100

/// Indikator sync yang selalu terlihat + peringatan (PRD K-27..K-29). Ketuk untuk sync sekarang.
class SyncStatusBar extends StatelessWidget {
  const SyncStatusBar(this.state, {super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final last = state.lastSyncAt;
    final tz = state.snapshot?.outlet.timezone ?? 'Asia/Jakarta';
    final warnings = [
      if (state.revoked) 'Device ini dicabut owner. Data baru tidak bisa dikirim.',
      if (state.stalePending) 'Ada data belum terkirim lebih dari 24 jam. Cari sinyal lalu ketuk bar ini.',
      if (state.clockWarning) 'Jam HP selisih lebih dari 5 menit dari server. Perbaiki jam HP.',
      if (state.rejectedCount > 0) '${state.rejectedCount} data ditolak server. Lihat menu Masalah sync.',
      if (state.needsUpdate) 'Versi aplikasi terlalu lama. Update sebelum buka shift berikutnya.',
    ];
    // Offline tetap kuning, bukan biru, supaya langsung terlihat beda.
    final fg = state.online ? Sky.c800 : _offlineFg;
    return Material(
      color: state.online ? Sky.c100 : _offlineBg,
      child: InkWell(
        onTap: state.syncNow,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: fg),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(state.online ? Icons.cloud_done : Icons.cloud_off, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(state.online ? 'Online' : 'Offline', style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('Menunggu ${state.pending}'),
                const SizedBox(width: 12),
                Text(last == null ? 'Belum pernah sync' : 'Sync ${jam(outletTime(last, tz))}'),
              ]),
              for (final w in warnings) Text(w, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Data yang ditolak server (status REJECTED) beserta alasannya (PRD K-27).
class SyncProblemsPage extends StatelessWidget {
  const SyncProblemsPage(this.state, {super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Masalah sync')),
        body: FutureBuilder<List<OutboxRow>>(
          future: state.store.rejected(),
          builder: (context, result) {
            final rows = result.data ?? const <OutboxRow>[];
            if (rows.isEmpty) return const EmptyState(Icons.check_circle_outline, 'Tidak ada data yang ditolak server.');
            return ListView(children: [
              const ListTile(
                title: Text('Data di bawah ditolak server dan tidak dikirim ulang. Foto layar ini dan laporkan ke owner.'),
              ),
              for (final r in rows) ListTile(title: Text('${r.type} · ${r.createdAt}'), subtitle: Text(r.lastError ?? '-')),
            ]);
          },
        ),
      );
}
