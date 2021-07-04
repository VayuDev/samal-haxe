package samal;

import haxe.Exception;


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
    static private function toCppGCTypeRec(type : Datatype) : String {
        switch(type) {
            case Int:
                return "int_";
            case Bool:
                return "bool_";
            case List(base):
                return "list_S" + toCppGCTypeRec(base) + "E";
            case _:
                throw new Exception("TODO " + type);
        }
    }
    static public function toCppGCTypeStr(type : Datatype) : String {
        return "samalds::" + toCppGCTypeRec(type);
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
}