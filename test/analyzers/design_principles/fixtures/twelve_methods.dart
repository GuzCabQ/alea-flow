// Expected: 1 SRP violation issue (12 public methods > default limit of 10).

class TwelveMethodClass {
  void methodOne() {}
  void methodTwo() {}
  void methodThree() {}
  void methodFour() {}
  void methodFive() {}
  void methodSix() {}
  void methodSeven() {}
  void methodEight() {}
  void methodNine() {}
  void methodTen() {}
  void methodEleven() {}
  void methodTwelve() {}
}
