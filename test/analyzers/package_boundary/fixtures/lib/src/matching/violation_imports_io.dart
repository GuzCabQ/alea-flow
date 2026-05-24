// Expected: 1 issue, severity blocker, line 4.
// Matching library is pure — no I/O is allowed.

import 'dart:io';

bool exists(String path) => File(path).existsSync();
