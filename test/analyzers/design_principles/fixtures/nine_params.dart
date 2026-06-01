// Expected: 1 coupling issue (9 constructor params > default limit of 7).

class NineParamClass {
  NineParamClass(
    String a,
    String b,
    String c,
    String d,
    String e,
    String f,
    String g,
    String h,
    String i,
  );
}
