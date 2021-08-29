package samal.lang;

import samal.lang.generated.SamalAST.IdentifierWithTemplate;
import haxe.Exception;

using samal.lang.Util.NullTools;
using samal.lang.Util.Util;

enum UsertypeSubtype {
    Struct;
    Enum;
}


enum Datatype {
    Int;
    Bool;
    List(baseType : Datatype);
    Unknown(name : String, templateParams : Array<Datatype>);
    Function(returnType : Datatype, params : Array<Datatype>);
    Tuple(elements : Array<Datatype>);
    Usertype(name : String, templateParams : Array<Datatype>, type : UsertypeSubtype);
}

class DatatypeNotFound extends Exception {
    public function new(typeNotFound) {
        super('Type $typeNotFound not found!');
    }
}

abstract class StringToDatatypeMapper {
    abstract public function getDatatype(name : String, templateParams : Array<Datatype>) : Datatype;
}

class StringToDatatypeMapperUsingTypeMap extends StringToDatatypeMapper {
    final mTypeMap : Map<String, Datatype>;
    public function new(typeMap : Map<String, Datatype>) {
        mTypeMap = typeMap;
    }
    public function getDatatype(name : String, templateParams : Array<Datatype>) : Datatype {
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
    static public function getUnknownTypeData(type : Datatype) : IdentifierWithTemplate {
        switch(type) {
            case Unknown(name, params):
                return IdentifierWithTemplate.create(name, params);
            case _:
                throw new Exception(type + " is not a user type!");
        }
    }
    static public function getUsertypeMangledName(type : Datatype) : String {
        switch(type) {
            case Usertype(name, params, subtype):
                return subtype + "_" + Util.mangle(name, params);
            case _:
                throw new Exception(type + " is not a usertype!");
        }
    }
    static public function complete(type : Datatype, map : StringToDatatypeMapper) : Datatype {
        switch(type) {
            case Unknown(name, params):
                return map.getDatatype(name, params);
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
            case Usertype(name, templateParams, subtype):
                return Datatype.Usertype(name, templateParams.map(function(f) return complete(f, map)), subtype);
        }
    }
    static public function isComplete(type : Datatype) : Bool {
        switch(type) {
            case Unknown(name, params):
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
            case Usertype(name, templateParams, subtype):
                return !templateParams.any(function(p) {
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
            case Usertype(name, params, subtype):
                return getUsertypeMangledName(type);
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
            case Usertype(name, [], subtype):
                return name;
            case Usertype(name, params, subtype):
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
            case Usertype(name, params, subtype):
                return Std.string(subtype).toLowerCase() + "_s" + Util.mangle(name, params) + "e";
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
            case Usertype(_, _, _):
                // TODO check if type actually needs GC
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
            case Usertype(name, params, Struct):
                return "static samalrt::Datatype " + typeStr + "{samalrt::DatatypeCategory::Struct};\n";
            case Usertype(name, params, Enum):
                return "static samalrt::Datatype " + typeStr + "{samalrt::DatatypeCategory::Enum};\n";
            case _:
                throw new Exception("TODO requiresGC " + type);
        }
        throw new Exception("TODO toCppGCTypeDeclaration" + type);
    }
    public static function deepEquals(a : Datatype, b : Datatype) : Bool {
        return Std.string(a) == Std.string(b);
    }
}