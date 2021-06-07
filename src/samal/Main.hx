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

    var parser = new Parser("fn test() -> int {\n 5\n 3\n}");
    var ast = parser.parse();
    Log.trace(ast.dump(), null);
  }
}

