package samal;

import haxe.Log;
import samal.Tokenizer.TokenType;
import samal.Tokenizer.Token;
import samal.Program;

class Main {
  static function main() {
    /*var t = new Tokenizer("fn test() -> int {\n 5\n}");
    while(t.current().getType() != TokenType.Invalid) {
      trace(t.current().info());
      t.next();
    }*/

    var parser = new Parser("
fn test() -> int {
  {
    5 + 3
  }
  2
}");
    var ast = parser.parse();
    var program = new SamalProgram("Test");
    program.addModule("Main", ast);

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
  }
}

