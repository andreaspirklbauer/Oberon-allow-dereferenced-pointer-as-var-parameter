MODULE Test;
  IMPORT Texts, Oberon;

TYPE
  r0 = RECORD i : INTEGER; END;
  r1 = RECORD (r0) x : REAL END;
  r2 = RECORD (r1) c : CHAR END;
  p0 = POINTER TO r0;
  p1 = POINTER TO r1;
  p2 = POINTER TO r2;

VAR W : Texts.Writer;

PROCEDURE check(VAR r : r0);
BEGIN
  IF r IS r2 THEN Texts.WriteString(W, "is r2")
  ELSIF r IS r1 THEN Texts.WriteString(W, "is r1")
  ELSIF r IS r0 THEN Texts.WriteString(W, "is r0")
  END ;
  Texts.WriteLn(W)
END check;

PROCEDURE Go* ();
  VAR p : p0;  r : r0; q : p2; t : r2;
BEGIN
  NEW(p); NEW(q);
  check(t);
  check(p^);
  check(q^);
  p := q;  check(p^);
  Texts.Append(Oberon.Log, W.buf)
END Go;

BEGIN
  Texts.OpenWriter(W);
END Test.

ORP.Compile Test.Mod/s ~
System.Free Test ~
Test.Go ~

-> should generate the following output

is r2
is r0
is r2
is r2






