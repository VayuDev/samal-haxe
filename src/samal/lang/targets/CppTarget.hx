package samal.lang.targets;
import haxe.Exception;
import samal.lang.Program.CppProgram;
import samal.lang.CppAST;
import samal.lang.targets.LanguageTarget;
using samal.lang.Datatype.DatatypeHelpers;
using samal.lang.Util.NullTools;

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
        if(!statement.getDatatype().requiresGC()) {
            return "";
        }
        return "; samalrt::SamalGCTracker " + statement.getVarName() 
            + "$$$tracker" + "{$ctx, " + "(void*) &" + statement.getVarName() 
            + ", " + statement.getDatatype().toCppGCTypeStr() + "}";
    }

    public function getLiteralInt(value : Int) : String {
        return "(int32_t) (" + Std.string(value) + "ll)";
    }
    public function getLiteralChar(value : String) : String {
        return Std.string(value.charCodeAt(0).sure());
    }
    public function getLiteralEmptyList() : String {
        return "nullptr";
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
        } else if(cppCtx.getHos() == Source) {
            ret += '#include "${node.getName()}.hpp"\n';
            ret += "\n";
            // used datatypes
            final alreadyDeclared = [];
            for(d in node.getUsedDatatypes()) {
                ret += d.toCppGCTypeDeclaration(alreadyDeclared);
            }
            // now assign the fields to the structs. We need to do it in this order, because structs can be recursive.
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
    public function makeStructDeclaration(ctx : SourceCreationContext, node : CppStructDeclaration) : String {
        final cppCtx = cast(ctx, CppContext);
        if(cppCtx.getHos() != HeaderStart) {
            return "";
        }
        final reversedFields = node.getFields().copy();
        reversedFields.reverse();

        return 
            "#pragma pack(push, 1)\n"
            + "struct " + node.getDatatype().toCppType() + " {\n"
            + node.getFields().map(function(f) {
                return " " + f.getDatatype().toCppType() + " " + f.getFieldName() + ";\n";
            }).join("")
            + "};\n"
            + "namespace samalrt {\n"
            + "inline samalrt::SamalString inspect(samalrt::SamalContext& ctx, const " + node.getDatatype().toCppType() + "& value) {\n"
            + ' samalrt::SamalString ret = samalrt::toSamalString(ctx, "}");\n'
            + reversedFields.map(function(f) {
                return ' ret = samalrt::listConcat(ctx, inspect(ctx, value.${f.getFieldName()}), ret);\n'
                    + ' ret = samalrt::listConcat(ctx, samalrt::toSamalString(ctx, "${f.getFieldName()} = "), ret);\n';
            }).join(' ret = samalrt::listConcat(ctx, samalrt::toSamalString(ctx, ", "), ret);\n')
            + ' ret = samalrt::listConcat(ctx, samalrt::toSamalString(ctx, "${node.getDatatype().toSamalType()}{"), ret);\n'
            + " return ret;\n"
            + "}\n"
            + "}\n"
            + "#pragma pack(pop)\n";
    }
    public function makeEnumDeclaration(ctx : SourceCreationContext, node : CppEnumDeclaration) : String {
        final cppCtx = cast(ctx, CppContext);
        if(cppCtx.getHos() != HeaderStart) {
            return "";
        }
        return
            "#pragma pack(1)\n"
            + "struct " + node.getDatatype().toCppType() + " {\n"
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
            + "};\n";
    }
    public function makeScopeStatement(ctx : SourceCreationContext, node : CppScopeStatement) : String {
        return indent(ctx) + node.getScope().toSrc(this, ctx.next());
    }    
    public function makeBinaryExprStatement(ctx : SourceCreationContext, node : CppBinaryExprStatement) : String {
        return indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = " + node.getLhsVarName() + " " + opAsCppStr(node.getOp()) + " " + node.getRhsVarName() + getTrackerString(node);
    }    
    public function makeUnaryExprStatement(ctx : SourceCreationContext, node : CppUnaryExprStatement) : String {
        final ret = indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName();
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

    private function opAsCppStr(op : CppBinaryExprOp) : String {
        switch(op) {
            case Add:
                return "+";
            case Sub:
                return "-";
            case Mul:
                return "*";
            case Div:
                return "/";
            case Less:
                return "<";
            case More:
                return ">";
            case LessEqual:
                return "<=";
            case MoreEqual:
                return ">=";
            case Equal:
                return "==";
            case NotEqual:
                return "!=";
        }
    }
}