package samal;

#if sys
import sys.FileSystem;
import sys.io.File;
#end
import samal.CppAST.HeaderOrSource;
import samal.CppAST.CppContext;
import haxe.display.Display.Platform;
import haxe.Log;
import samal.Tokenizer.TokenType;
import samal.Tokenizer.Token;
import samal.Program;

import cloner.Cloner;

class Main {
  static function main() {
    /*var t = new Tokenizer("fn test() -> int {\n 5\n}");
    while(t.current().getType() != TokenType.Invalid) {
      trace(t.current().info());
      t.next();
    }*/

    var parser = new Parser("Main", "
module A.B.Main

fn add(a : int, b : int) -> int {
  a + b
}

fn fib(n : int) -> int {
  if n < 2 {
    n
  } else {
    fib(n - 1) + fib(n - 2)
  }
}

fn reverseHelper<T>(la : [T], lb : [T]) -> [T] {
  match la {
    [head + tail] -> {
      reverseHelper<T>(tail, head + lb)
    }
    [] -> {
      lb
    }
  }
}

fn reverse<T>(l : [T]) -> [T] {
  reverseHelper<T>(l, [:T])
}

fn sum<T>(l : [T]) -> T {
  self = sum<T>
  match l {
    [] -> {
      0
    }
    [head + tail] -> {
      head + self(tail)
    }
  }
}

fn seq(n : int) -> [int] {
  if n < 1 {
    [n]
  } else {
    n + seq(n - 1)
  }
}

fn mainTwo() -> [int] {
  a = seq
  list = a(10000)
  reverse<int>(sum<int>(list) + list)
}

fn map<S, T>(l : [S], callback : fn(S) -> T) -> [T] {
  match l {
    [] -> [:T]
    [head + tail] -> callback(head) + map<S, T>(tail, callback)
  }
}

fn main() -> int {
  a = {
    outer = 1
    fn(param : int) -> int {
      inner = 5
      outer + param + inner
    }
  }
  a(10)
}");


    var ast = parser.parse();
    var program = new SamalProgram();
    program.addModule(ast);

    Log.trace("@@@@ Stage 1 @@@@", null);
    var stage1 = new Stage1(program);
    program = stage1.completeGlobalIdentifiers();
    Log.trace(program.dump(), null);

    Log.trace("@@@@ Stage 2 @@@@", null);
    var stage2 = new Stage2(program);
    program = stage2.completeDatatypes();
    Log.trace(program.dump(), null);

    Log.trace("@@@@ Stage 3 @@@@", null);
    var stage3 = new Stage3(program);
    var cprogram = stage3.convertToCppAST();
    Log.trace(cprogram.dump(), null);

    var mainFunction = Util.mangle("A.B.Main.main", []);

#if sys
    cprogram.forEachModule(function(mod, ast) {
      try {
        FileSystem.createDirectory("out");
      } catch(_) {}
      File.saveContent('out/${mod}.hpp', ast.toCpp(new CppContext(0, HeaderOrSource.Header, mainFunction)));
      File.saveContent('out/${mod}.cpp', ast.toCpp(new CppContext(0, HeaderOrSource.Source, mainFunction)));

    });
    File.copy("samal_runtime/samal_runtime.cpp", "out/samal_runtime.cpp");
    File.copy("samal_runtime/samal_runtime.hpp", "out/samal_runtime.hpp");
#end
  }
}

