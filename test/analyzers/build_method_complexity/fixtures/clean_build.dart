// Expected: 0 issues.
// A build() method with shallow nesting (depth 2) and few lines.

class CleanWidget {
  Widget build(BuildContext context) {
    return Column(children: [Text('hello'), Text('world')]);
  }
}
