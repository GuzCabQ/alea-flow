// Expected: 1 nesting issue (depth 6 > default max 4).

class DeepWidget {
  Widget build(BuildContext context) {
    return A(
      children: [
        B(
          children: [
            C(
              children: [
                D(
                  children: [
                    E(
                      children: [
                        F(children: [Text('leaf')]),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
