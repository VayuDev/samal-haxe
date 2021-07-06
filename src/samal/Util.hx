package samal;

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