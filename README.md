# Oberon-allow-dereferenced-pointer-as-var-parameter
Modified Oberon compiler which handles dereferenced pointers as VAR parameters correctly

Note: In this repository, the term "Project Oberon 2013" refers to a re-implementation of the original "Project Oberon" on an FPGA development board around 2013, as published at www.projectoberon.com.

**PREREQUISITES**: A current version of Project Oberon 2013 (see http://www.projectoberon.com). If you use Extended Oberon (see http://github.com/andreaspirklbauer/Oberon-extended), the functionality is already implemented.

------------------------------------------------------
**Problem description**

The current (as of January 2021) release of the Project Oberon 2013 compiler does not handle dereferenced pointers p^ correctly when they are passed as VAR parameters to a procedure.

For example, in the test program below, the last call to *check* in procedure *Go*

      p := q;  check(p^);

outputs "is r0" instead of "is r2". This is because the compiler passes the *static* type of *p* (namely *p0*) to procedure *check* instead of its *dynamic* type (namely *p2*).

     MODULE Test;
       IMPORT Texts, Oberon;

     TYPE r0 = RECORD i : INTEGER; END;
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

     is r2
     is r0
     is r2
     is r2  <------ here the PO2013 compiler outputs "is r0" instead of "is r2"

------------------------------------------------------
**Solution**

The solution is to check whether the parameter has been dereferenced. If this is the case, pass its dynamic type instead of the static type. This changes procedure *ORG.VarParam*

From:

     PROCEDURE VarParam*(VAR x: Item; ftype: ORB.Type);
       VAR xmd: INTEGER;
     BEGIN xmd := x.mode; loadAdr(x);
       ...
       ELSIF ftype.form = ORB.Record THEN
         IF xmd = ORB.Par THEN Put2(Ldr, RH, SP, x.a+4+frame); incR ELSE loadTypTagAdr(x.type) END
       END
     END VarParam;

To:

     PROCEDURE VarParam*(VAR x: Item; ftype: ORB.Type);
       VAR xmd: INTEGER;
     BEGIN xmd := x.mode; loadAdr(x);
       ...
       ELSIF ftype.form = ORB.Record THEN
         IF x.deref THEN Put2(Ldr, RH, x.r, -8); incR    (*pass the dynamic type rather than the static type here*)
         ELSIF xmd = ORB.Par THEN Put2(Ldr, RH, SP, x.a+4+frame); incR
         ELSE loadTypTagAdr(x.type)
         END
       END
     END VarParam;

------------------------------------------------------
**DOWNLOADING AND BUILDING THE MODIFIED COMPILER**

Download the files from the [**Sources/ExtendedOberon**](Sources/ExtendedOberon) directory of this repository.

Convert the downloaded files to Oberon format (Oberon uses CR as line endings) using the command [**dos2oberon**](dos2oberon), also available in this repository (example shown for Mac or Linux):

     for x in *.Mod ; do ./dos2oberon $x $x ; done

Import the files to your Oberon system. If you use an emulator (e.g., **https://github.com/pdewacht/oberon-risc-emu**) to run the Oberon system, click on the *PCLink1.Run* link in the *System.Tool* viewer, copy the files to the emulator directory, and execute the following command on the command shell of your host system:

     cd oberon-risc-emu
     for x in *.Mod ; do ./pcreceive.sh $x ; sleep 1 ; done

Create the modified Oberon compiler:

     ORP.Compile ORS.Mod/s ORB.Mod/s ~
     ORP.Compile ORG.Mod/s ORP.Mod/s ~
     ORP.Compile ORL.Mod/s ORX.Mod/s ORTool.Mod/s ~
     System.Free ORTool ORP ORG ORB ORS ORL ORX ~

------------------------------------------------------
**DIFFERENCES TO PROJECT OBERON 2013**

**ORG.Mod**

```diff
--- FPGAOberon2013/ORG.Mod	2019-05-30 17:58:14.000000000 +0200
+++ Oberon-allow-dereferenced-pointer-as-var-parameter/Sources/FPGAOberon2013/ORG.Mod	2021-01-13 09:23:02.000000000 +0100
@@ -22,7 +22,7 @@
       mode*: INTEGER;
       type*: ORB.Type;
       a*, b*, r: LONGINT;
-      rdo*: BOOLEAN  (*read only*)
+      rdo*, selected*, deref*, unused: BOOLEAN  (*read only, selected in record or array, dereferenced*)
     END ;
 
   (* Item forms and meaning of fields:
@@ -247,7 +247,7 @@
   END MakeStringItem;
 
   PROCEDURE MakeItem*(VAR x: Item; y: ORB.Object; curlev: LONGINT);
-  BEGIN x.mode := y.class; x.type := y.type; x.a := y.val; x.rdo := y.rdo;
+  BEGIN x.mode := y.class; x.type := y.type; x.a := y.val; x.rdo := y.rdo; x.selected := FALSE; x.deref := FALSE;
     IF y.class = ORB.Par THEN x.b := 0
     ELSIF (y.class = ORB.Const) & (y.type.form = ORB.String) THEN x.b := y.lev  (*len*) ;
     ELSE x.r := y.lev
@@ -258,7 +258,7 @@
   (* Code generation for Selectors, Variables, Constants *)
 
   PROCEDURE Field*(VAR x: Item; y: ORB.Object);   (* x := x.y *)
-  BEGIN;
+  BEGIN x.deref := FALSE;
     IF x.mode = ORB.Var THEN
       IF x.r >= 0 THEN x.a := x.a + y.val
       ELSE loadAdr(x); x.mode := RegI; x.a := y.val
@@ -270,7 +270,7 @@
 
   PROCEDURE Index*(VAR x, y: Item);   (* x := x[y] *)
     VAR s, lim: LONGINT;
-  BEGIN s := x.type.base.size; lim := x.type.len;
+  BEGIN s := x.type.base.size; lim := x.type.len; x.deref := FALSE;
     IF (y.mode = ORB.Const) & (lim >= 0) THEN
       IF (y.a < 0) OR (y.a >= lim) THEN ORS.Mark("bad index") END ;
       IF x.mode IN {ORB.Var, RegI} THEN x.a := y.a * s + x.a
@@ -313,7 +313,7 @@
     ELSIF x.mode = RegI THEN Put2(Ldr, x.r, x.r, x.a); NilCheck
     ELSIF x.mode # Reg THEN ORS.Mark("bad mode in DeRef")
     END ;
-    x.mode := RegI; x.a := 0; x.b := 0
+    x.mode := RegI; x.a := 0; x.b := 0; x.deref := TRUE
   END DeRef;
 
   PROCEDURE Q(T: ORB.Type; VAR dcw: LONGINT);
@@ -682,7 +682,10 @@
       IF x.type.len >= 0 THEN Put1a(Mov, RH, 0, x.type.len) ELSE  Put2(Ldr, RH, SP, x.a+4+frame) END ;
       incR
     ELSIF ftype.form = ORB.Record THEN
-      IF xmd = ORB.Par THEN Put2(Ldr, RH, SP, x.a+4+frame); incR ELSE loadTypTagAdr(x.type) END
+      IF x.deref THEN Put2(Ldr, RH, x.r, -8); incR
+      ELSIF xmd = ORB.Par THEN Put2(Ldr, RH, SP, x.a+4+frame); incR
+      ELSE loadTypTagAdr(x.type)
+      END
     END
   END VarParam;
```

**ORP.Mod**

Note: The modification in *ORP.selector* (set *x.selected*) is strictly speaking not necessary for this fix.

```diff
--- FPGAOberon2013/ORP.Mod	2020-03-13 14:23:55.000000000 +0100
+++ Oberon-allow-dereferenced-pointer-as-var-parameter/Sources/FPGAOberon2013/ORP.Mod	2021-01-12 15:46:57.000000000 +0100
@@ -121,7 +121,7 @@
     VAR y: ORG.Item; obj: ORB.Object;
   BEGIN
     WHILE (sym = ORS.lbrak) OR (sym = ORS.period) OR (sym = ORS.arrow)
-        OR (sym = ORS.lparen) & (x.type.form IN {ORB.Record, ORB.Pointer}) DO
+        OR (sym = ORS.lparen) & (x.type.form IN {ORB.Record, ORB.Pointer}) DO x.selected := TRUE;
       IF sym = ORS.lbrak THEN
         REPEAT ORS.Get(sym); expression(y);
           IF x.type.form = ORB.Array THEN
```