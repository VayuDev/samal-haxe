package samal.lang.targets;
import samal.lang.Stage2.VarDeclaration;
import haxe.Exception;
import samal.lang.Program.CppProgram;
import samal.lang.CppAST;
import samal.lang.targets.LanguageTarget;
using samal.lang.Datatype.DatatypeHelpers;
using samal.lang.Util.NullTools;

using samal.lang.targets.CppDatatypeHelpers;

enum HeaderOrSource {
    HeaderStart;
    HeaderEnd;
    Source;
}

class CppContext extends SourceCreationContext {
    final mHos : HeaderOrSource;
    final mProgram : CppProgram;

    public function new(indent : Int, mainFunction : String, hos : HeaderOrSource, program : CppProgram) {
        super(indent, mainFunction);
        mHos = hos;
        mProgram = program;
    }

    public function getHos() {
        return mHos;
    }
    public override function next() : CppContext {
        return new CppContext(mIndent + 1, mMainFunction, mHos, mProgram);
    }
    public override function prev() : CppContext {
        return new CppContext(mIndent - 1, mMainFunction, mHos, mProgram);
    }
    public function getProgram() : CppProgram {
        return mProgram;
    }
}

class CppTarget extends LanguageTarget {
    public function new() {}

    private function getTrackerString(statement : CppStatement) : String {
        if(!statement.getDatatype().isContainerType()) {
            return "";
        }
        return "; samalrt::SamalGCTracker " + statement.getVarName() 
            + "$$$tracker" + "{$ctx, " + "(void*) &" + statement.getVarName() 
            + ", " + statement.getDatatype().toCppGCTypeStr() + "}";
    }

    public function getLiteralBool(value : Bool) : String {
        return value ? "true" : "false";
    }
    public function getLiteralByte(value : Int) : String {
        return "((uint8_t) " + Std.string(value) + ")";
    }
    public function getLiteralChar(value : String) : String {
        return "(char32_t) (" + Std.string(value.charCodeAt(0).sure()) + ")";
    }
    public function getLiteralInt(value : Int) : String {
        return "(int32_t) (" + Std.string(value) + "ll)";
    }
    public function getLiteralEmptyList(baseType : Datatype) : String {
        return "(samalrt::List<" + baseType.toCppType() + ">*) nullptr";
    }
    private function toCppTupleDeclaration(type : Datatype, alreadyDone : Array<Datatype>, program : CppProgram) : String {
        for(done in alreadyDone) {
            if(DatatypeHelpers.deepEquals(done, type)) {
                return "";
            }
        }
        switch(type) {
            case Int, Bool, Char, Byte:
                return "";
            case List(baseType):
                return toCppTupleDeclaration(baseType, alreadyDone, program);
            case Usertype(name, templateParams, actualType):
                final typeDecl = program.findUsertypeDeclaration(type);
                if(Std.isOfType(typeDecl, CppStructDeclaration)) {
                    final structDecl = cast(typeDecl, CppStructDeclaration);
                    var ret = "";
                    for(f in structDecl.getFields()) {
                        ret += toCppTupleDeclaration(f.getDatatype(), alreadyDone, program) + "\n";
                    }
                    return ret;
                }
                if(Std.isOfType(typeDecl, CppEnumDeclaration)) {
                    final enumDecl = cast(typeDecl, CppEnumDeclaration);
                    var ret = "";
                    for(v in enumDecl.getVariants()) {
                        for(f in v.getFields()) {
                            ret += toCppTupleDeclaration(f.getDatatype(), alreadyDone, program) + "\n";
                        }
                    }
                    return ret;
                }
                throw new Exception("TODO");
            case Function(returnType, params):
                return toCppTupleDeclaration(returnType, alreadyDone, program) 
                    + params.map(function(p) return toCppTupleDeclaration(p, alreadyDone, program)).join("\n");
            case Tuple(elements):
                alreadyDone.push(type);
                var ret = "";
                for(e in elements) {
                    ret += toCppTupleDeclaration(e, alreadyDone, program);
                }
                final guardStr = "_SAMAL_TUPLE_DECL_" + type.toCppGCTypeStr();
                ret += "#ifndef " + guardStr + "\n";
                ret += "#define " + guardStr + "\n";
                ret += "namespace samalrt {\n";
                ret += "namespace tuples {\n";
                ret += "struct " + type.toCppTupleBaseTypename() + " {" + "\n";
                ret += Util.seq(elements.length).map(function(i) return " " + elements[i].toCppType() + " e" + i + ";\n").join("");
                ret += "};\n";
                ret += "};\n";
                // inspect
                ret += "inline samalrt::SamalString inspect(samalrt::SamalContext& ctx, const " + type.toCppType() + "& value) {\n"
                    + ' samalrt::SamalString ret = samalrt::toSamalString(ctx, ")");\n'
                    + Util.seq(elements.length).map(function(i) {
                        return ' ret = samalrt::listConcat(ctx, inspect(ctx, value.e${elements.length - i - 1}), ret);\n';
                    }).join(' ret = samalrt::listConcat(ctx, samalrt::toSamalString(ctx, ", "), ret);\n')
                    + ' ret = samalrt::listConcat(ctx, samalrt::toSamalString(ctx, "("), ret);\n'
                    + " return ret;\n"
                    + "}\n";
                ret += "};\n";
                ret += "#endif\n";
                return ret;
            case Unknown(_, _):
                throw new Exception("ASSERT!");
        }
    }
    public function makeFile(ctx : SourceCreationContext, node : CppFile) : String {
        var ret = "";
        final cppCtx = Std.downcast(ctx, CppContext);
        if(cppCtx.getHos() == HeaderStart) {
            ret += "#pragma once\n";
            ret += "#include <cstdint>\n";
            ret += "#include <cstring>\n";
            ret += "#include <cmath>\n";
            ret += "#include <iostream>\n";
            ret += "#include <cassert>\n";
            ret += "#include <functional>\n";
            ret += "#include \"samal_runtime.hpp\"\n";
            ret += "\n";
            // declare tuples
            final alreadyDeclaredTuples = [];
            for(d in node.getUsedDatatypes()) {
                ret += StringTools.trim(toCppTupleDeclaration(d, alreadyDeclaredTuples, cppCtx.getProgram()));
            }
            ret += "\n";
        } else if(cppCtx.getHos() == Source) {
            ret += '#include "${node.getName()}.hpp"\n';
            ret += "\n";
            // this is for declaring the Datatype-objects for GC tracking
            final alreadyDeclared = [];
            for(d in node.getUsedDatatypes()) {
                ret += d.toCppGCTypeDeclaration(alreadyDeclared);
            }
            // now assign the fields to the structs/enums. We can't do this in the prev step, because structs/enums can be recursive.
            ret += "\n";
            var placerCounter = 0;
            for(declaredType in alreadyDeclared) {
                if(declaredType.match(Usertype(_, _, Enum))) {
                    for(variantIndex => variant in cast(cppCtx.getProgram().findUsertypeDeclaration(declaredType), CppEnumDeclaration).getVariants()) {
                        for(fieldIndex => field in variant.getFields()) {
                            ret += 'static samalrt::DatatypeEnumPlacer placer$placerCounter{${declaredType.toCppGCTypeStr()}, $variantIndex, $fieldIndex, ${field.getDatatype().toCppGCTypeStr()}};\n';
                            placerCounter += 1;
                        }
                    }
                }
                else if(declaredType.match(Usertype(_, _, Struct))) {
                    for(i => field in cast(cppCtx.getProgram().findUsertypeDeclaration(declaredType), CppStructDeclaration).getFields()) {
                        ret += 'static samalrt::DatatypeStructPlacer placer$placerCounter{${declaredType.toCppGCTypeStr()}, $i, ${field.getDatatype().toCppGCTypeStr()}};\n';
                        placerCounter += 1;
                    }
                }
            }
        }
        ret += "\n";
        ret += node.getDeclarations().map((decl) -> (decl.toSrc(this, ctx))).filter(function(d) return d != "").join("\n\n");
        ret += "\n";
        return ret;
    }
    public function makeScopeNode(ctx : SourceCreationContext, node : CppScopeNode) : String {
        return "{\n" + node.getStatements().map((stmt) -> stmt.toSrc(this, ctx.next()) + ";\n").join("") + indent(ctx.prev()) + "}";
    }    
    public function makeFunctionDeclaration(ctx : SourceCreationContext, node : CppFunctionDeclaration) : String {
        final cppCtx = Std.downcast(ctx, CppContext);
        if(cppCtx.getHos() == HeaderStart) {
            return "";
        }
        
        final paramsAsStrArray = node.getParams().map((p) -> '${p.getDatatype().toCppType()} ${p.getName()}');
        var ret = node.getDatatype().getReturnType().toCppType() + " " + node.getMangledName() + "(" 
            + ["samalrt::SamalContext &$ctx"].concat(paramsAsStrArray).join(", ") + ")";

        if(cppCtx.getHos() == HeaderEnd) {
            ret += ";";
        } else {
            ret += " {\n";
            ret += " while(true) {\n";
            // trackers for params
            ret += node.getParams().map(function(p) {
                return indent(ctx.next()) + "samalrt::SamalGCTracker " + p.getName() + "$$$tracker" 
                    + "{$ctx, " + "(void*) &" + p.getName() + ", " + p.getDatatype().toCppGCTypeStr() + ", true};\n";
            }).join("");
            ret += node.getBody().getStatements().map((stmt) -> stmt.toSrc(this, ctx.next().next()) + ";\n").join("");
            ret += " }\n";
            ret += "}";
            if(node.getMangledName() == ctx.getMainFunctionMangledName()) {
                ret += '\nint main(int argc, char **argv) {
    samalrt::SamalContext ctx;
    auto res = ${node.getMangledName()}(ctx);
    std::cout << samalrt::inspect(ctx, res) << \"\\n\";
}';
            }
        }
        return ret;
    }
    private static function genEqualityCheckCode(nodeErrorInfo : String, datatype : Datatype, lhsName : String, rhsName : String) : String {
        switch(datatype) {
        case Int, Bool, Char, Byte:
            return 'if($lhsName != $rhsName) return false;\n';
        case List(_), Usertype(_, _, _):
            return  'if(!equals(ctx, $lhsName, $rhsName)) return false;\n';
        case Function(_, _), Tuple(_):
            throw new Exception(nodeErrorInfo + ": Unsupported datatype " + datatype.toSamalType());
        case Unknown(_, _):
            throw new Exception(nodeErrorInfo + ": Unknown datatype, this is a bug!");
        }
    }
    public function makeStructDeclaration(ctx : SourceCreationContext, node : CppStructDeclaration) : String {
        final cppCtx = cast(ctx, CppContext);
        if(cppCtx.getHos() != HeaderStart) {
            return "";
        }
        final reversedFields = node.getFields().copy();
        reversedFields.reverse();
        final nodeCppType = node.getDatatype().toCppType();
        return 
            "#pragma pack(push, 1)\n"
            + "struct " + node.getDatatype().toCppType() + " {\n"
            + node.getFields().map(function(f) {
                return " " + f.getDatatype().toCppType() + " " + f.getFieldName() + ";\n";
            }).join("")
            + "};\n"
            + "namespace samalrt {\n"
            + "inline samalrt::SamalString inspect(samalrt::SamalContext& ctx, const " + nodeCppType + "& value) {\n"
            + ' samalrt::SamalString ret = samalrt::toSamalString(ctx, "}");\n'
            + reversedFields.map(function(f) {
                return ' ret = samalrt::listConcat(ctx, inspect(ctx, value.${f.getFieldName()}), ret);\n'
                    + ' ret = samalrt::listConcat(ctx, samalrt::toSamalString(ctx, "${f.getFieldName()} = "), ret);\n';
            }).join(' ret = samalrt::listConcat(ctx, samalrt::toSamalString(ctx, ", "), ret);\n')
            + ' ret = samalrt::listConcat(ctx, samalrt::toSamalString(ctx, "${node.getDatatype().toSamalType()}{"), ret);\n'
            + " return ret;\n"
            + "}\n"
            + "inline bool equals(samalrt::SamalContext& ctx, const " + nodeCppType + "& a, const " + nodeCppType + "& b) {\n"
            + node.getFields().map(function(f) : String {
                return " " + genEqualityCheckCode(node.errorInfo(), f.getDatatype(), "a." + f.getFieldName(), "b." + f.getFieldName());
            }).join('')
            + " return true;\n"
            + "}\n"
            + "}\n"
            + "#pragma pack(pop)\n";
    }
    public function makeEnumDeclaration(ctx : SourceCreationContext, node : CppEnumDeclaration) : String {
        final cppCtx = cast(ctx, CppContext);
        if(cppCtx.getHos() != HeaderStart) {
            return "";
        }
        final nodeCppType = node.getDatatype().toCppType();
        return
            "#pragma pack(1)\n"
            + "struct " + nodeCppType + " {\n"
            + " int32_t variant;\n"
            + " union {\n"
            + node.getVariants().map(function(v) {
                return 
                    "  struct {\n" + v.getFields().map(function(f) {
                        return "   " + f.getDatatype().toCppType() + " " + f.getFieldName() + ";\n";
                    }).join("")
                    + "  } " + v.getName() + ";\n";
            }).join("")
            + " };\n"
            + "};\n"
            + "namespace samalrt {\n"
            + "inline bool equals(samalrt::SamalContext& ctx, const " + nodeCppType + "& a, const " + nodeCppType + "& b) {\n"
            + " if(a.variant != b.variant) return false;\n"
            + " switch(a.variant) {\n"
            + Util.seq(node.getVariants().length).map(function(variantIndex) : String {
                var ret = "  case " + variantIndex + ": {\n";
                final v = node.getVariants()[variantIndex];
                for(f in v.getFields()) {
                    ret += "   " + genEqualityCheckCode(node.errorInfo(), f.getDatatype(), 'a.${v.getName()}.${f.getFieldName()}', 'b.${v.getName()}.${f.getFieldName()}');
                }
                ret += "   break;\n";
                ret += "  }\n";
                return ret;
            }).join('')
            + " }\n"
            + " return true;\n"
            + "}\n"
            + "}\n";
    }
    public function makeScopeStatement(ctx : SourceCreationContext, node : CppScopeStatement) : String {
        return indent(ctx) + node.getScope().toSrc(this, ctx.next());
    }    
    public function makeBinaryExprStatement(ctx : SourceCreationContext, node : CppBinaryExprStatement) : String {
        var opStr : String = "";
        switch(node.getOp()) {
            case Equal, NotEqual:
                return indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = " + (node.getOp() == NotEqual ? "!" : "") 
                    + "samalrt::equals($ctx, " + node.getLhsVarName() + ", " + node.getRhsVarName() + ")" + getTrackerString(node);
            case Add:
                opStr = "+";
            case Sub:
                opStr = "-";
            case Mul:
                opStr = "*";
            case Div:
                opStr = "/";
            case Less:
                opStr = "<";
            case More:
                opStr = ">";
            case LessEqual:
                opStr = "<=";
            case MoreEqual:
                opStr = ">=";
            case And:
                opStr = "&&";
            case Or:
                opStr = "||";
        }
        return indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = " 
            + node.getLhsVarName() + " " + opStr + " " + node.getRhsVarName() + getTrackerString(node);
    }    
    public function makeUnaryExprStatement(ctx : SourceCreationContext, node : CppUnaryExprStatement) : String {
        var ret = indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName();
        switch(node.getOp()) {
            case Not:
                ret += " = !(" + node.getExpr() + ")" + getTrackerString(node);
            case ListGetHead:
                ret += " = (" + node.getExpr() + ")->value" + getTrackerString(node);
            case ListGetTail:
                ret += " = (" + node.getExpr() + ")->next" + getTrackerString(node);
            case ListIsEmpty:
                ret += " = !(" + node.getExpr() + ")" + getTrackerString(node);
        }
        return ret;
    }
    public function makeUnreachable(ctx : SourceCreationContext, node : CppUnreachable) : String {
        return indent(ctx) + " assert(false)";
    }
    public function makeAssignmentStatement(ctx : SourceCreationContext, node : CppAssignmentStatement) : String {
        switch(node.getType()) {
            case JustDeclare:
                return indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = " + node.getDatatype().toCppDefaultInitializationString() + getTrackerString(node);
            case JustAssign:
                return indent(ctx) + node.getVarName() + " = " + node.getRhsVarName();
            case DeclareAndAssign:
                return indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() +  " = " + node.getRhsVarName() + getTrackerString(node);
        }
    }    
    public function makeReturnStatement(ctx : SourceCreationContext, node : CppReturnStatement) : String {
        return indent(ctx) + "return " + node.getVarName();
    }
    public function makeFunctionCallStatement(ctx : SourceCreationContext, node : CppFunctionCallStatement) : String {
        return indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = " + node.getFunctionName() + "(" + ["$ctx"].concat(node.getParams()).join(", ") + ")" + getTrackerString(node);
    }
    public function makeIfStatement(ctx : SourceCreationContext, node : CppIfStatement) : String {
        return indent(ctx) + "if (" + node.getConditionVarName() + ") " + node.getMainBody().toSrc(this, ctx.next()) + " else " + node.getElseBody().toSrc(this, ctx.next());
    }
    public function makeListPrependStatement(ctx : SourceCreationContext, node : CppListPrependStatement) : String {
        return indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = samalrt::listPrepend<" + node.getDatatype().getBaseType().toCppType() + ">($ctx, " + node.getValue() + ", " + node.getList() + ")" + getTrackerString(node);
    }
    public function makeNativeStatement(ctx : SourceCreationContext, node : CppNativeStatement) : String {
        final s = node.findSnippet("cpp");
        if(s == null) {
            throw new Exception(node.errorInfo() + ": Missing native snippet for C++");  
        }
        return indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = " + node.getDatatype().toCppDefaultInitializationString() + getTrackerString(node) + ";\n"
            + indent(ctx) + "{\n"
            + indent(ctx.next()) + s
            + indent(ctx) + "}";
    }
    public function makeCreateEnumStatement(ctx : SourceCreationContext, node : CppCreateEnumStatement) : String {
        final cppCtx = cast(ctx, CppContext);
        final program = cppCtx.getProgram();
        final decl = cast(program.findUsertypeDeclaration(node.getDatatype()), CppEnumDeclaration);
        final variantInfo = Util.findEnumVariant(decl.getVariants(), node.getVariantName());
        return 
            indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = " + node.getDatatype().toCppType() + "{"
            + ".variant = " + variantInfo.index + ", "
            + "." + variantInfo.variant.getName() + " = {"
            + node.getParams().map(function(p) {
                return "." + p.name + " = " + p.value;
            }).join(", ") + "}}" + getTrackerString(node);
    }
    
    public function makeCreateLambdaStatement(ctx : SourceCreationContext, node : CppCreateLambdaStatement) : String {
        final bufferVarName = "buffer$$$" + Util.getUniqueId();
        final extractCapturedVarsString = if(node.getCapturedVariables().length > 0) {
            indent(ctx.next()) + "uint8_t* " + bufferVarName + " = (uint8_t*)$ctx.getLambdaCapturedVarPtr() + sizeof(void*);\n"
            + node.getCapturedVariables().map(function(p) {
                return 
                    indent(ctx.next()) + p.getDatatype().toCppType() + " " + p.getName() + ";\n"
                    + indent(ctx.next()) + "memcpy(&" + p.getName() + ", " + bufferVarName + ", " + p.getDatatype().toCppGCTypeStr() + ".getSizeOnStack());\n"
                    + indent(ctx.next()) + bufferVarName + " += " + p.getDatatype().toCppGCTypeStr() + ".getSizeOnStack();\n";
            }).join("");
        } else {
            "";
        }
        // first the lambda itself
        var ret = 
            indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = *[](samalrt::SamalContext& $ctx, "
            + node.getParams().map(function(p) return p.getDatatype().toCppType() + " " + p.getName()).join(", ") + ") -> " + node.getDatatype().getReturnType().toCppType() + " {\n"
            + extractCapturedVarsString
            + node.getBody().getStatements().map(function(stmt) return stmt.toSrc(this, ctx.next()) + ";").join("\n")
            + "\n" + indent(ctx) + "};\n";
        // then the buffer creation
        ret += indent(ctx.next()) + "uint8_t* " + bufferVarName + " = (uint8_t*) $ctx.alloc(" + "("
            + node.getCapturedVariables().map(function(p) {
                return p.getDatatype().toCppGCTypeStr() + ".getSizeOnStack()";
            }).join(" + ") + "+ sizeof(void*)));\n";
        // assign it to the function
        ret += indent(ctx.next()) + node.getVarName() + ".setCapturedData(" + bufferVarName + ", {" + node.getCapturedVariables().map(function(p) return "&" + p.getDatatype().toCppGCTypeStr()).join(", ") + "});\n";
        
        // the the memcpys
        ret += indent(ctx.next()) + bufferVarName + " += sizeof(void*);\n";
        ret += node.getCapturedVariables().map(function(capturedVar) {
            return 
                indent(ctx.next()) + "memcpy(" + bufferVarName + ", &" + capturedVar.getName() + ", " + capturedVar.getDatatype().toCppGCTypeStr() + ".getSizeOnStack());\n"
                + indent(ctx.next()) + bufferVarName + " += " + capturedVar.getDatatype().toCppGCTypeStr() + ".getSizeOnStack()";
        }).join(";\n");
       return ret + "\n" + indent(ctx) + getTrackerString(node);
    }
    public function makeCreateStructStatement(ctx : SourceCreationContext, node : CppCreateStructStatement) : String {
        final paramsStr = node.getParams().map(function(p) return "." + p.name + " = " + p.value).join(", ");
        return indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = " + node.getDatatype().getUsertypeMangledName() + "{" + paramsStr + "}" + getTrackerString(node);
    }
    public function makeCreateTupleStatement(ctx : SourceCreationContext, node : CppCreateTupleStatement) : String {
        return indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = " 
            + node.getDatatype().toCppType() + "{" + node.getParams().join(", ") + "}";
    }
    public function makeEnumIsVariantStatement(ctx : SourceCreationContext, node : CppEnumIsVariantStatement) : String {
        return indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = " + node.getEnumExpr() + ".variant == " + node.getVariantIndex() + getTrackerString(node);
    }
    public function makeFetchEnumFieldStatement(ctx : SourceCreationContext, node : CppFetchEnumFieldStatement) : String {
        return indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = " + node.getEnumExpr() + "." + node.getVariantName() + "." + node.getFieldName();
    }
    public function makeTailCallSelf(ctx : SourceCreationContext, node : CppTailCallSelf) : String {
        var ret = "";
        for(param in node.getParams()) {
            ret += indent(ctx) + param.paramName + " = " + param.paramValue + ";\n";
        }
        ret += indent(ctx) + "continue";
        return ret;
    }
}