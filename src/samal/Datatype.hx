package samal;

import samal.AST.IdentifierWithTemplate;
import haxe.Exception;

using samal.Util.NullTools;
using samal.Util.Util;


enum Datatype {
    Int;
    Bool;
    List(baseType : Datatype);
    Usertype(name : String, templateParams : Array<Datatype>);
    Function(returnType : Datatype, params : Array<Datatype>);
    Tuple(elements : Array<Datatype>);
}

class DatatypeHelpers {
    static public function getReturnType(type : Datatype) : Datatype {
        switch(type) {
            case Function(returnType, _):
                return returnType;
            case _:
                throw new Exception(type + " is not a function!");
        }
    }
    static public function getBaseType(type : Datatype) : Datatype {
        switch(type) {
            case List(baseType):
                return baseType;
            case _:
                throw new Exception(type + " is not a list!");
        }
    }
    static public function getUserTypeData(type : Datatype) : IdentifierWithTemplate {
        switch(type) {
            case Usertype(name, params):
                return new IdentifierWithTemplate(name, params);
            case _:
                throw new Exception(type + " is not a user type!");
        }
    }
    static public function complete(type : Datatype, map : Map<String, Datatype>) : Datatype {
        switch(type) {
            case Usertype(name, params):
                return map[name].sure();
            case List(base):
                return Datatype.List(complete(base, map));
            case Function(returnType, params):
                return Datatype.Function(complete(returnType, map), params.map(function(paramType) {
                    return complete(paramType, map);
                }));
            case Tuple(params):
                return Datatype.Tuple(params.map(function(paramType) {
                    return complete(paramType, map);
                }));
            case Int:
                return type;
            case Bool:
                return type;
        }
    }
    static public function isComplete(type : Datatype) : Bool {
        switch(type) {
            case Usertype(name, params):
                return false;
            case List(base):
                return isComplete(base);
            case Function(returnType, params):
                if(!isComplete(returnType)) {
                    return false;
                }
                return !params.any(function(p) {
                    return !isComplete(p);
                });
            case Tuple(params):
                return !params.any(function(p) {
                    return !isComplete(p);
                });
            case Int:
                return true;
            case Bool:
                return true;
        }
    }
    static public function toCppType(type : Datatype) : String {
        switch(type) {
            case Int:
                return "int32_t";
            case Bool:
                return "bool";
            case List(base):
                return "samalrt::List<" + toCppType(base) + ">*";
            case _:
                throw new Exception("TODO " + type);
        }
    }
    static public function toMangledName(type : Datatype) : String {
        switch(type) {
            case Int:
                return "int_";
            case Bool:
                return "bool_";
            case List(base):
                return "list_s" + toMangledName(base) + "e";
            case _:
                throw new Exception("TODO " + type);
        }
    }
    static public function toCppGCTypeStr(type : Datatype) : String {
        return "samalds::" + toMangledName(type);
    }
    static public function requiresGC(type : Datatype) : Bool {
        switch(type) {
            case Int:
                return false;
            case Bool:
                return false;
            case List(base):
                return true;
            case _:
                throw new Exception("TODO " + type);
        }
    }
    public static function deepEquals(a : Datatype, b : Datatype) : Bool {
        return Std.string(a) == Std.string(b);
    }
}