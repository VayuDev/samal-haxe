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
    public static function createIndentStr(indent : Int) : String {
        var ret = "";
        for(i in 0...indent) {
            ret += " ";
        }
        return ret;
    }
    
    public static function mangle(identifier : String, templateParams : Array<Datatype>) {
        if(templateParams.length == 0 && !StringTools.contains(identifier, ".")) {
            return identifier;
        }
        // TODO proper implementation
        return StringTools.replace(identifier, ".", "_") + "$";
    }

    private static var uniqueIdCounter = 0;
    public static function getUniqueId() : Int {
        return uniqueIdCounter++;
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