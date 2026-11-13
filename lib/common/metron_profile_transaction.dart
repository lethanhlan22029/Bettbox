import 'dart:io';

/// Replaces a validated profile and restores its file and runtime on failure.
Future<void> installMetronProfile({
  required File staged,
  required File target,
  required Future<void> Function() apply,
  required Future<void> Function() rollback,
}) async {
  final suffix = DateTime.now().microsecondsSinceEpoch;
  final pending = File('${target.path}.$suffix.install');
  final backup = File('${target.path}.$suffix.backup');
  final existed = await target.exists();
  var settled = false;
  var replaced = false;
  try {
    await target.parent.create(recursive: true);
    if (existed) await target.copy(backup.path);
    await staged.copy(pending.path);
    await pending.rename(target.path);
    replaced = true;
    await apply();
    settled = true;
  } on Object {
    if (replaced) {
      if (existed) {
        await backup.copy(pending.path);
        await pending.rename(target.path);
      } else if (await target.exists()) {
        await target.delete();
      }
      await rollback();
    }
    settled = true;
    rethrow;
  } finally {
    try {
      if (await pending.exists()) await pending.delete();
    } on Object {
      // Cleanup must not turn a committed update into a reported failure.
    }
    // Keep recovery data if restoring either the file or runtime failed.
    try {
      if (settled && await backup.exists()) await backup.delete();
    } on Object {
      // A leftover backup can be removed later without affecting the profile.
    }
  }
}
