package samal.lang;

import samal.lang.CppAST.TailCallSelfParam;
import samal.lang.Datatype.DatatypeHelpers;
using samal.lang.Datatype.DatatypeHelpers;
import haxe.Exception;
import samal.lang.AST;
import samal.lang.generated.SamalAST;

class Util {

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
            ret.set(expectedParams[i].getUnknownTypeData().getName(), passedParams[i]);
        }

        return ret;
    }

    public static function findEnumVariant(haystack : Array<EnumDeclVariant>, needle : String) : {index : Int, variant : EnumDeclVariant} {
        
        for(i => variant in haystack) {
            if(variant.getName() == needle) {
                return {index : i, variant: variant};
            }
        }
        throw new Exception("Enum variant " + needle + " not found");
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
}

interface Cloneable {
    public function clone() : Cloneable;
}

class NullTools {
    public static function sure<T>(value:Null<T>):T {
        if (value == null) {
            throw new Exception("null pointer in .sure() call");
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