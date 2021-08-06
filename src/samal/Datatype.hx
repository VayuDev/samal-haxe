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
    Struct(name : String, templateParams : Array<Datatype>);
}

class DatatypeNotFound extends Exception {
    public function new(typeNotFound) {
        super('Type $typeNotFound not found!');
    }
}

abstract class StringToDatatypeMapper {
    abstract public function getDatatype(name : String) : Datatype;
}

class StringToDatatypeMapperUsingTypeMap extends StringToDatatypeMapper {
    final mTypeMap : Map<String, Datatype>;
    public function new(typeMap : Map<String, Datatype>) {
        mTypeMap = typeMap;
    }
    public function getDatatype(name : String) : Datatype {
        final value = mTypeMap[name];
        if(value == null) {
            throw new DatatypeNotFound(name);
        }
        return value.sure();
    }
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
    static public function getParams(type : Datatype) : Array<Datatype> {
        switch(type) {
            case Function(_, params):
                return params;
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
    static public function getStructMangledName(type : Datatype) : String {
        switch(type) {
            case Struct(name, params):
                return "struct_" + Util.mangle(name, params);
            case _:
                throw new Exception(type + " is not a struct type!");
        }
    }
    static public function complete(type : Datatype, map : StringToDatatypeMapper) : Datatype {
        switch(type) {
            case Usertype(name, params):
                return map.getDatatype(name);
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
            case Struct(name, templateParams):
                return Datatype.Struct(name, templateParams.map(function(f) return complete(f, map)));
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
            case Struct(name, fields):
                return !fields.any(function(p) {
                    return !isComplete(p);
                });
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
            case Function(returnType, params):
                return "samalrt::Function<" + toCppType(returnType) + "(samalrt::SamalContext&, " + params.map(function(p) return toCppType(p)).join(", ") + ")>";
            case Struct(name, params):
                return getStructMangledName(type);
            case _:
                throw new Exception("TODO toCppType: " + type);
        }
    }
    static public function toSamalType(type : Datatype) : String {
        switch(type) {
            case Int:
                return "int";
            case Bool:
                return "bool";
            case List(base):
                return "[" + toCppType(base) + "]";
            case Struct(name, []):
                return name;
            case Struct(name, params):
                return name + "<" + params.map(function(p) return toSamalType(p)).join(", ") + ">";
            case _:
                throw new Exception("TODO toSamalType: " + type);
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
            case Function(returnType, params):
                return "fn_s" + toMangledName(returnType) + "_" + params.map(function(p) return toMangledName(p)).join("_") + "e";
            case Struct(name, params):
                return "struct_s" + Util.mangle(name, params) + "e";
            case _:
                throw new Exception("TODO " + type);
        }
    }
    static public function toCppGCTypeStr(type : Datatype) : String {
        return toMangledName(type);
    }
    static public function requiresGC(type : Datatype) : Bool {
        switch(type) {
            case Int:
                return false;
            case Bool:
                return false;
            case List(_):
                return true;
            case Function(_, _):
                return true;
            case Struct(_, _):
                return true;
            case _:
                throw new Exception("TODO requiresGC" + type);
        }
    }
    static public function toCppDefaultInitializationString(type : Datatype) : String {
        switch(type) {
            case Int:
                return "0";
            case Bool:
                return "false";
            case List(_):
                return "{ 0 }";
            case Function(_, _):
                return "{}";
            case _:
                throw new Exception("TODO toDefaultInitializationString" + type);
        }
    }
    static public function toCppGCTypeDeclaration(type : Datatype, alreadyDone : Array<Datatype>) : String {
        for(done in alreadyDone) {
            if(deepEquals(done, type)) {
                return "";
            }
        }
        final typeStr = toCppGCTypeStr(type);
        alreadyDone.push(type);
        switch(type) {
            case Int:
                return "static const samalrt::Datatype " + typeStr + "{samalrt::DatatypeCategory::Int};\n";
            case Bool:
                return "static const samalrt::Datatype " + typeStr + "{samalrt::DatatypeCategory::Bool};\n";
            case List(base):
                return toCppGCTypeDeclaration(base, alreadyDone) 
                    + "static const samalrt::Datatype " + typeStr +  "{samalrt::DatatypeCategory::List, &" + toCppGCTypeStr(base) + "};\n";
            case Function(returnType, params):
                return toCppGCTypeDeclaration(returnType, alreadyDone) 
                    + params.map(function(p) {
                        return toCppGCTypeDeclaration(p, alreadyDone);
                    }).join("")
                    + "static const samalrt::Datatype " + typeStr +  "{samalrt::DatatypeCategory::Function, &" 
                    + toCppGCTypeStr(returnType) + ", {" + params.map(function(p) return "&" + toCppGCTypeStr(p)).join(", ") + "}};\n";
            case Struct(name, params):
                return "static samalrt::Datatype " + typeStr + "{samalrt::DatatypeCategory::Struct};\n";
            case _:
                throw new Exception("TODO requiresGC " + type);
        }
        throw new Exception("TODO toCppGCTypeDeclaration" + type);
    }
    public static function deepEquals(a : Datatype, b : Datatype) : Bool {
        return Std.string(a) == Std.string(b);
    }
}