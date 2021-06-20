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
}