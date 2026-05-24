// Expected: 1 issue, severity blocker, line 4.
// Contracts must not depend on dart:io — they are meant to be pure.

import 'dart:io';

void touch(File f) {
  f.existsSync();
}
