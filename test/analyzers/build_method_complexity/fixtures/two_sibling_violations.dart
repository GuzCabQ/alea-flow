// Expected: 2 nesting issues (two separate over-deep sibling branches).

class TwoViolationsWidget {
  Widget build(BuildContext context) {
    return Row(
      children: [
        // First deep branch (depth 5)
        A(
          children: [
            B(
              children: [
                C(
                  children: [
                    D(children: [Text('left-leaf')]),
                  ],
                ),
              ],
            ),
          ],
        ),
        // Second deep branch (depth 5)
        W(
          children: [
            X(
              children: [
                Y(
                  children: [
                    Z(children: [Text('right-leaf')]),
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
