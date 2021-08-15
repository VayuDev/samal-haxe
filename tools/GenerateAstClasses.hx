package tools;

import haxe.Exception;
import sys.io.File;
import samal.Tokenizer;

enum Access {
    ReadWrite;
    Read;
    ReadWriteNullable;
}

typedef Field = {access : Access, name : String, datatype : String, datatypeTokens : Array<String>};
typedef GeneratedClass = {fields : Array<Field>, parent : Null<String>, customCodeSnippets : Array<String>};
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
        eat();
        eatSubstr("start_hx");
        mTokenizer.push();
        while(mTokenizer.current().getSubstr() != "@" && mTokenizer.peek(1).getSubstr() != "end_hx") {
            eat();
        }
        var substr = mTokenizer.acceptAndGetSubstring();
        eatSubstr("@");
        eatSubstr("end_hx");
        mTokenizer.skipNewlines();
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
            customCodeSnippets: []});
        final customCodeSnippets : Array<String> = [];
        while(mTokenizer.current().getType() != Invalid) {
            mTokenizer.skipNewlines();
            if(current().getType() == At) {
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
            mTokenizer.skipNewlines();
            while(current().getSubstr() != "}") {
                if(current().getSubstr() == "@") {
                    classCustomCodeSnippets.push(parseCodeSnippet());
                } else {
                    fields.push(parseField());
                }
                mTokenizer.skipNewlines();
            }
            eatSubstr("}");

            generatedClasses.set(className, {fields: fields, parent: parent, customCodeSnippets: classCustomCodeSnippets});
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
        var ret = "import samal.AST;\nimport samal.Tokenizer.SourceCodeRef;\n\n";

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
            ret += " public function new(" 
                + allParams.map(function(f) { 
                    return "p" + toCamelCase(f.name) + " : " + f.datatype;
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
                    return "p" + toCamelCase(f.name) + " : " + f.datatype;
                }).join(", ") 
                + ") {\n";
            ret += "  return new " + className + "(";
            ret += allParams.map(function(f) {
                if(f.access == ReadWriteNullable)
                    return "null";
                return "p" + toCamelCase(f.name);
            }).join(", ");
            ret += ");\n";
            ret += " }\n";

            // now getters and setters
            for(field in fields) {
                ret += " public function get" + toCamelCase(field.name) + "() : " + field.datatype + " {\n";
                ret += "  return m" + toCamelCase(field.name) + ";\n";
                ret += " }\n";
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
                +  "function replace(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) : " 
                +  className + " {\n";
            if(isAST) {
                ret += "  final self = preorder(this);\n";
                ret += "  self.replaceChildren(preorder, postorder);\n";
                ret += "  return cast(postorder(self), " + className + ");\n";
            } else {
                ret += "  replaceChildren(preorder, postorder);\n";
                ret += "  return this;\n";
            }
            ret += " }\n";

            // now clone
            ret += " public " + (isAST ? "override " : "") + "function clone() : " + className + " {\n";
            ret += "  return new " + className + "(\n";
            ret += allParams.map(function(f) {
                if(isGeneratedClass(f.datatype)) {
                    return "   m" + toCamelCase(f.name) + ".clone()";
                }
                return "   m" + toCamelCase(f.name);
            }).join(",\n") + "\n";
            ret += "  );\n";
            ret += " }\n";

            // now dumpSelf
            ret += " public " + (isAST ? "override " : "") + "function dumpSelf() : String {\n";
            ret += "  return ";
            if(isAST)
                ret += "super.dumpSelf() + \"-\" + ";
            allParams.map(function(f) {
                if(f.datatype == "String" || f.datatype == "Datatype") {
                    ret += "m" + toCamelCase(f.name) + " + \", \" + ";
                }
            });
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
    private function generateFieldReplaceString(field : Field) : String {
        if(isASTNode(field.datatype)) {
            return "  m" + toCamelCase(field.name) + " = m" + toCamelCase(field.name) + ".replace(preorder, postorder);\n";
        }
        if(field.datatypeTokens[0] == "Array") {
            final subType = field.datatypeTokens[2];
            return "  this.m" + toCamelCase(field.name) + " = m" + toCamelCase(field.name) 
                + ".map(function(node :  " + subType +  ") : " + subType + " {\n"
                + "   return node.replace(preorder, postorder);\n"
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
        trace(res);
    }
}