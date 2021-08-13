package samal;

import samal.SamalAST.SamalExpression;
import samal.Datatype.DatatypeHelpers;
using samal.Datatype.DatatypeHelpers;
import haxe.Exception;
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
        var base = StringTools.replace(identifier, ".", "_");
        if(templateParams.length == 0) {
            return base;
        }
        return base + "_S" + templateParams.map(function (type) { return DatatypeHelpers.toMangledName(type); }).join("_") + "E";
    }

    public static function buildTemplateReplacementMap(expectedParams : Array<Datatype>, passedParams : Array<Datatype>) : Map<String, Datatype> {
        if(expectedParams.length != passedParams.length) {
            throw new Exception('Expected & passed template parameter amount doesn\'t match; expected ${expectedParams.length}, but got ${passedParams.length}');
        }
        final ret = new Map<String, Datatype>();
        for(i in 0...expectedParams.length) {
            ret.set(expectedParams[i].getUserTypeData().getName(), passedParams[i]);
        }

        return ret;
    }

    private static var uniqueIdCounter = 0;
    public static function getUniqueId() : Int {
        return uniqueIdCounter++;
    }

    @generic
    public static function any<T>(list : Array<T>, condition : (T) -> Bool) : Bool {
        for(e in list) {
            if(condition(e)) {
                return true;
            }
        }
        return false;
    }

    public static function createNamedAndValuedParametersArray(names : Array<String>, values : Array<SamalExpression>) {
        if(names.length != values.length) {
            throw new Exception("Lengthes must match!");
        }
        var ret : Array<NamedAndValuedParameter> = [];
        for(i in 0...names.length) {
            ret.push(new NamedAndValuedParameter(names[i], values[i]));
        }
        return ret;
    }
}

interface Cloneable {
    public function clone() : Cloneable;
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