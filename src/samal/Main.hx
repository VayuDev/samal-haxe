package samal;

import haxe.Log;
import samal.Tokenizer.TokenType;
import samal.Tokenizer.Token;

class Main {
  static function main() {
    /*var t = new Tokenizer("fn test() -> int {\n 5\n}");
    while(t.current().getType() != TokenType.Invalid) {
      trace(t.current().info());
      t.next();
    }*/

    var parser = new Parser("fn test() -> int {\n 5+ 3\n}");
    var ast = parser.parse();
    var program = new Program();
    program.addModule("Main", ast);

    var stage1 = new Stage1(program);
    program = stage1.completeGlobalIdentifiers();

    var stage2 = new Stage2(program);
    program = stage2.completeDatatypes();

    Log.trace(program.dump(), null);
  }
}

