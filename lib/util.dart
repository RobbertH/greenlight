String _p2(int v) => v.toString().padLeft(2, '0');

String fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}-${_p2(d.month)}-${_p2(d.day)}';
}

String fmtTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_p2(d.hour)}:${_p2(d.minute)}:${_p2(d.second)}'
      '.${(d.millisecond ~/ 100)}';
}

String fmtDateTime(int ms) => '${fmtDate(ms)} ${fmtTime(ms)}';

String fmtCountdown(int msRemaining) {
  final s = (msRemaining / 1000).ceil();
  if (s < 60) return '$s s';
  return '${s ~/ 60}:${_p2(s % 60)}';
}
