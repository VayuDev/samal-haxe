package samal;

import samal.AST;

class Util {
    public static function escapeString(str : String) {
        var ret = "";
        for(i in 0...str.length) {
            var ch = str.charAt(i);
            switch(ch) {
                case "\n":
                    ret += "\\n";
                case _:
                    ret += ch;
            }
        }
        return ret;
    }

    @:generic
    public static function replaceNodes<T>(nodes : Array<T>, preorder : (ASTNode) -> (ASTNode), postorder : (ASTNode) -> (ASTNode)) : Array<T> {
        var ret : Array<T> = [];
        for(node in nodes) {
            ret.push(cast cast(node, ASTNode).replace(preorder, postorder));
        }
        return ret;
    }
}

class NullTools {
    public static function sure<T>(value:Null<T>):T {
      if (value == null) {
        throw "null pointer in .sure() call";
      }
      return @:nullSafety(Off) (value:T);
    }
    public static function or<T>(value:Null<T>, defaultValue:T):T {
      if (value == null) {
        return defaultValue;
      }
      return @:nullSafety(Off) (value:T);
    }
  }