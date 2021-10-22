package samal.lang.targets;

import samal.lang.Datatype;
using samal.lang.Datatype.DatatypeHelpers;
import haxe.Exception;

class CppDatatypeHelpers {
    static public function toCppTupleBaseTypename(type : Datatype) : String {
        switch(type) {
            case Tuple(elements):
                return "TS" + elements.map(function(e) return e.toMangledName()).join("_") + "TE";
            case _:
                throw new Exception("Not a tuple!");
        }
    }
    static public function toCppType(type : Datatype) : String {
        switch(type) {
            case Int:
                return "int32_t";
            case Bool:
                return "bool";
            case Char:
                return "char32_t";
            case List(base):
                return "samalrt::List<" + toCppType(base) + ">*";
            case Function(returnType, params):
                return "samalrt::Function<" + toCppType(returnType) + "(samalrt::SamalContext&, " + params.map(function(p) return toCppType(p)).join(", ") + ")>";
            case Usertype(name, params, subtype):
                return type.getUsertypeMangledName();
            case Tuple(elements):
                return "samalrt::tuples::" + toCppTupleBaseTypename(type);
            case _:
                throw new Exception("TODO toCppType: " + type);
        }
    }
    static public function toCppGCTypeStr(type : Datatype) : String {
        return type.toMangledName();
    }
    static public function toCppDefaultInitializationString(type : Datatype) : String {
        switch(type) {
            case Int:
                return "0";
            case Bool:
                return "false";
            case Char:
                return "0";
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
            if(type.deepEquals(done)) {
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
            case Char:
                return "static const samalrt::Datatype " + typeStr + "{samalrt::DatatypeCategory::Char};\n";
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
            case Tuple(elements):
                return "static samalrt::Datatype " + typeStr + "{samalrt::DatatypeCategory::Enum};\n";
            case _:
                throw new Exception("TODO  " + type);
        }
        throw new Exception("TODO toCppGCTypeDeclaration" + type);
    }
}