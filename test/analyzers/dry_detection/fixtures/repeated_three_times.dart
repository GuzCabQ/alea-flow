// Expected: 1 DRY issue — the string 'my_repeated_literal_key' appears 3×
// (length 23 ≥ default min_length 10, count 3 ≥ default min_occurrences 3).

void main() {
  final a = 'my_repeated_literal_key';
  final b = 'my_repeated_literal_key';
  final c = 'my_repeated_literal_key';
  print('$a $b $c');
}
