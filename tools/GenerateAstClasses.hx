package tools;

import haxe.Exception;
import sys.io.File;
import samal.bootstrap.Tokenizer;

enum Access {
    ReadWrite;
    Read;
    ReadWriteNullable;
}

typedef Field = {access : Access, name : String, datatype : String, datatypeTokens : Array<String>};
typedef GeneratedClass = {fields : Array<Field>, parent : Null<String>, customCodeSnippets : Array<String>, constructorCodeSnippet : String, constructorParamsSnippet : String};
typedef ParsingResult = {generatedClasses : Map<String, GeneratedClass>, customCode : Array<String>}

class Generator {
    final mTokenizer : Tokenizer;
    public function new(path : String) {
        var contents = File.getContent(path);
        mTokenizer = new Tokenizer(contents, DisableMulticharRecognition);
    }

    function current() : Token {
        return mTokenizer.current();
    }

    function eatSubstr(substr : String) {
        if(current().getSubstr() != substr) {
            throw new Exception("Expected " + substr + ", got: " + current().getSubstr());
        }
        eat();
    }
    function eat() {
        mTokenizer.eat(current().getType());
    }

    function parseField() : Field {
        var access : Access;
        if(current().getSubstr() == "+") {
            access = Access.ReadWrite;
        } else if(current().getSubstr() == "-") {
            access = Access.Read;
        } else if(current().getSubstr() == "#") {
            access = Access.ReadWriteNullable;
        } else {
            throw new Exception("You need specify the access of each field with a + or -, not '" + current().getSubstr() + "'");
        }
        eat();
        final name = current().getSubstr();
        eat();
        eatSubstr(":");
        var datatypeTokens = [];
        while(current().getType() != NewLine) {
            datatypeTokens.push(current().getSubstr());
            eat();
        }
        eatSubstr("\n");

        return {access: access, name: name, datatype: datatypeTokens.join(""), datatypeTokens: datatypeTokens};
    }

    private function parseCodeSnippet() : String {
        mTokenizer.push();
        while(mTokenizer.current().getSubstr() != "@" && mTokenizer.peek(1).getSubstr() != "end_hx") {
            eat();
        }
        var substr = mTokenizer.acceptAndGetSubstring();
        eatSubstr("@");
        eatSubstr("end_hx");
        return substr;
    }

    public function parse() : ParsingResult {
        final generatedClasses : Map<String, GeneratedClass> = new Map();
        generatedClasses.set("ASTNode", {
            fields: [{
                access: Read, 
                name: "sourceCodeRef", 
                datatype: "SourceCodeRef", 
                datatypeTokens: ["SourceCodeRef"]}], 
            parent: null,
            customCodeSnippets: [],
            constructorCodeSnippet: "",
            constructorParamsSnippet: ""});
        final customCodeSnippets : Array<String> = [];
        while(mTokenizer.current().getType() != Invalid) {
            mTokenizer.skipNewlines();
            if(current().getType() == At) {
                eatSubstr("@");
                eatSubstr("start_hx");
                customCodeSnippets.push(parseCodeSnippet());
                continue;
            }
            eatSubstr("class");
            final className = current().getSubstr();
            eat();
            var parent = null;
            if(current().getSubstr() == "extends") {
                eat();
                parent = current().getSubstr();
                eat();
            }
            eatSubstr("{");
            var fields : Array<Field> = [];
            var classCustomCodeSnippets : Array<String> = [];
            var constructorCodeSnippet = "";
            var constructorParamsSnippet = "";
            mTokenizer.skipNewlines();
            while(current().getSubstr() != "}") {
                if(current().getSubstr() == "@") {
                    if(mTokenizer.peek().getSubstr() == "start_hx") {
                        eatSubstr("@");
                        eatSubstr("start_hx");
                        classCustomCodeSnippets.push(parseCodeSnippet());
                    } else if(mTokenizer.peek().getSubstr() == "start_hx_ctor") {
                        eatSubstr("@");
                        eatSubstr("start_hx_ctor");
                        eatSubstr("(");
                        mTokenizer.push();
                        while(current().getSubstr() != ")") {
                            mTokenizer.next();
                        }
                        constructorParamsSnippet = mTokenizer.acceptAndGetSubstring();
                        eatSubstr(")");
                        constructorCodeSnippet = parseCodeSnippet();
                    } else {
                        throw new Exception("Unknown line statement " + mTokenizer.peek());
                    }
                } else {
                    fields.push(parseField());
                }
                mTokenizer.skipNewlines();
            }
            eatSubstr("}");

            generatedClasses.set(className, {
                fields: fields, 
                parent: parent, 
                customCodeSnippets: classCustomCodeSnippets, 
                constructorCodeSnippet: constructorCodeSnippet, 
                constructorParamsSnippet: constructorParamsSnippet
            });
            mTokenizer.skipNewlines();
        }    
        return {generatedClasses: generatedClasses, customCode: customCodeSnippets};
    }
}

class Translator {
    private final mGeneratedClasses : Map<String, GeneratedClass>;
    private final mCustomCodeSnippets : Array<String>;
    public function new(parsingResult : ParsingResult) {
        mGeneratedClasses = parsingResult.generatedClasses;
        mCustomCodeSnippets = parsingResult.customCode;
    }
    public function translate() : String {
        var ret = "package samal.lang.generated;\nimport samal.lang.AST;\nimport samal.bootstrap.Tokenizer.SourceCodeRef;\n\n";

        for(snippet in mCustomCodeSnippets) {
            ret += snippet += "\n";
        }

        for(className => classInfo in mGeneratedClasses.keyValueIterator()) {
            if(className == "ASTNode") {
                continue;
            }
            ret += "class " + className;
            final fields = classInfo.fields;
            final parent = classInfo.parent;
            if(parent != null) {
                ret += " extends " + parent;
            }
            // now generate the actual body
            // first, we create the class fields
            ret += " {\n";
            for(field in fields) {
                ret += " var m";
                ret += toCamelCase(field.name);
                ret += " : ";
                if(field.access == ReadWriteNullable) {
                    ret += "Null<" + field.datatype + ">";
                } else {
                    ret += field.datatype;
                }
                ret += ";\n";
            }
            ret += "\n";
            // next, the constructor
            final parentParams = getAllParentConstructorFields(parent);
            final allParams = parentParams.concat(fields);
            ret += " function new(" 
                + allParams.map(function(f) { 
                    return "p" + toCamelCase(f.name) + " : " + getFieldDatatype(f);
                }).join(", ")
                + ") {\n";
            if(parent != null) {
                ret += "  super(" + parentParams.map(function(f) return "p" + toCamelCase(f.name)).join(", ") + ");\n";
            }
            for(field in fields) {
                ret += "  m" + toCamelCase(field.name) + " = p" + toCamelCase(field.name) + ";\n";
            }
            ret += " }\n";
            // now the static object-creator
            final filteredParentParams = filterClassExtensionFields(parentParams);
            final allFilteredParams = filteredParentParams.concat(filterClassExtensionFields(fields));
            ret += " public static function create(" 
                + allFilteredParams.map(function(f) { 
                    return "p" + toCamelCase(f.name) + " : " + getFieldDatatype(f);
                }).join(", ") 
                + (classInfo.constructorParamsSnippet == "" ? "" : ", " + classInfo.constructorParamsSnippet)
                + ") {\n";
            ret += "  final ret = new " + className + "(";
            ret += allParams.map(function(f) {
                if(f.access == ReadWriteNullable)
                    return "null";
                return "p" + toCamelCase(f.name);
            }).join(", ");
            ret += ");\n";
            ret += classInfo.constructorCodeSnippet;
            ret += "\nreturn ret;\n";
            ret += " }\n";
            // now the second constructor
            ret += " public static function createFull(" 
                + allParams.map(function(f) { 
                    return "p" + toCamelCase(f.name) + " : " + getFieldDatatype(f);
                }).join(", ") 
                + (classInfo.constructorParamsSnippet == "" ? "" : ", " + classInfo.constructorParamsSnippet)
                + ") {\n";
            ret += "  final ret = new " + className + "(";
            ret += allParams.map(function(f) {
                return "p" + toCamelCase(f.name);
            }).join(", ");
            ret += ");\n";
            ret += classInfo.constructorCodeSnippet;
            ret += "\n  return ret;\n";
            ret += " }\n";

            // now getters and setters
            for(field in fields) {
                ret += " public function get" + toCamelCase(field.name) + "() : " + getFieldDatatype(field) + " {\n";
                ret += "  return m" + toCamelCase(field.name) + ";\n";
                ret += " }\n";
                if(field.access != Read) {
                    ret += " public function set" + toCamelCase(field.name) + "(pNewValue : " + field.datatype + ") : Void {\n";
                    ret += "  m" + toCamelCase(field.name) + " = pNewValue;\n";
                    ret += " }\n";
                }
            }
            // now replaceChildren
            ret += " public " + (isASTNode(className) ? "override " : "") + "function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) : Void {\n";
            for(field in fields) {
                ret += generateFieldReplaceString(field);
            }
            ret += " }\n";
            // now replace
            final isAST = isASTNode(className);
            ret += " public " + (isAST ? "override " : "") 
                +  "function replace(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) : ";
            if(isAST) {
                ret += "ASTNode {\n";
                ret += "  final self = preorder(this);\n";
                ret += "  self.replaceChildren(preorder, postorder);\n";
                ret += "  return postorder(self);\n";
            } else {
                ret += className + " {\n";
                ret += "  replaceChildren(preorder, postorder);\n";
                ret += "  return this;\n";
            }
            ret += " }\n";
            // now clone
            ret += " public " + (isAST ? "override " : "") + "function clone() : " + className + " {\n";
            ret += "  return new " + className + "(\n";
            ret += allParams.map(function(f) {
                if(isGeneratedClass(f.datatype)) {
                    return "   cast(m" + toCamelCase(f.name) + ".clone(), " + f.datatype + ")";
                }
                else if(f.datatypeTokens[0] == "Array") {
                    return "   " + getFieldAttributeName(f) + ".map(function(e) return " + (isGeneratedClass(f.datatypeTokens[2]) ? "cast(e.clone(), " + f.datatypeTokens[2] + ")" : "") + ")";
                }
                return "   m" + toCamelCase(f.name);
            }).join(",\n") + "\n";
            ret += "  );\n";
            ret += " }\n";

            // now dumpSelf
            ret += " public " + (isAST ? "override " : "") + "function dumpSelf() : String {\n";
            ret += "  return ";
            if(isAST)
                ret += 'super.dumpSelf() + " " + ';
            for(f in fields) {
                if(isASTNode(f.datatype) || f.datatype == "SourceCodeRef") {
                    continue;
                }
                if(f.datatypeTokens[0] == "Array") {
                    continue;
                }
                ret += '"${f.name}=" + ';
                if(f.access == ReadWriteNullable) {
                    ret += "(" + getFieldAttributeName(f) + " == null ? \"()\" : '' + " + getFieldAttributeName(f) + ".sure())"; 
                } else if(isGeneratedClass(f.datatype)) {
                    ret += getFieldAttributeName(f) + ".dumpSelf()";
                } else if(f.datatype == "IdentifierWithTemplate") {
                    ret += getFieldAttributeName(f) + ".dump()";  
                } else  {
                    ret += getFieldAttributeName(f);
                }
                ret += " + \", \" + ";
            }
            ret += '""';
            ret += ";\n";
            ret += " }\n";


            // now custom snippets
            for(snippet in classInfo.customCodeSnippets) {
                ret += snippet + "\n";
            }

            ret += "}\n\n";
        }
        return ret;
    }
    private static function getFieldAttributeName(field : Field) {
        return "m" + toCamelCase(field.name);
    }
    private static function getFieldDatatype(field : Field) : String {
        if(field.access == ReadWriteNullable) {
            return "Null<" + field.datatype + ">";
        }
        return field.datatype;
    }
    private function generateFieldReplaceString(field : Field) : String {
        if(isASTNode(field.datatype)) {
            return "  m" + toCamelCase(field.name) + " = cast(m" + toCamelCase(field.name) + ".replace(preorder, postorder), " + field.datatype + ");\n";
        }
        if(field.datatypeTokens[0] == "Array") {
            final subType = field.datatypeTokens[2];
            return "  this.m" + toCamelCase(field.name) + " = m" + toCamelCase(field.name) 
                + ".map(function(node :  " + subType +  ") : " + subType + " {\n"
                + "   return cast(node.replace(preorder, postorder), " + subType + ");\n"
                + "  });\n";
        }
        
        return "";
    }
    private function getAllParentConstructorFields(parentName : Null<String>) : Array<Field> {
        if(parentName == null) {
            return [];
        }
        var ret = getAllParentConstructorFields(mGeneratedClasses[parentName].parent);
        ret = ret.concat(mGeneratedClasses[parentName].fields);
        return ret;
    }

    private static function toCamelCase(varName : String) : String {
        return varName.charAt(0).toUpperCase() + varName.substr(1);
    }
    private function isGeneratedClass(datatype : String) : Bool {
        return mGeneratedClasses.exists(datatype);
    }
    private function isASTNode(datatype : String) : Bool {
        while(true) {
            if(datatype == null) {
                return false;
            }
            if(datatype == "ASTNode") {
                return true;
            }
            if(!isGeneratedClass(datatype)) {
                return false;
            }
            datatype = mGeneratedClasses[datatype].parent;
        }
    }
    private function filterClassExtensionFields(fields : Array<Field>) : Array<Field> {
        var ret = [];
        for(field in fields) {
            if(field.access == ReadWriteNullable)
                continue;
            ret.push(field);
        }
        return ret;
    }
}

class GenerateAstClasses {
    static function main() {
        final result = new Generator("assets/SamalAST.hx.template");
        final classes = result.parse();
        final translator = new Translator(classes);
        final res = translator.translate();
        final outHandle = File.write("src/samal/lang/generated/SamalAST.hx");
        outHandle.writeString(res);
        outHandle.close();
    }
}