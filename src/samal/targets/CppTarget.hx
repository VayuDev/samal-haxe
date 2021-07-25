package samal.targets;
import samal.CppAST;
import samal.targets.LanguageTarget;
using samal.Datatype.DatatypeHelpers;
using samal.Util.NullTools;

enum HeaderOrSource {
    Header;
    Source;
}

class CppContext extends SourceCreationContext {
    var mHos : HeaderOrSource;

    public function new(indent : Int, hos : HeaderOrSource, mainFunction : String) {
        super(indent, mainFunction);
        mHos = hos;
    }

    public function isHeader() : Bool {
        return mHos == Header;
    }
    public function isSource() : Bool {
        return mHos == Source;
    }
    public override function next() : CppContext {
        return new CppContext(mIndent + 1, mHos, mMainFunction);
    }
    public override function prev() : CppContext {
        return new CppContext(mIndent - 1, mHos, mMainFunction);
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
    public function getLiteralEmptyList() : String {
        return "nullptr";
    }
    public function makeFile(ctx : SourceCreationContext, node : CppFile) : String {
        var ret = "";
        final cppCtx = Std.downcast(ctx, CppContext);
        if(cppCtx.isHeader()) {
            ret += "#include <cstdint>\n";
            ret += "#include <cstring>\n";
            ret += "#include <cmath>\n";
            ret += "#include <iostream>\n";
            ret += "#include <cassert>\n";
            ret += "#include <functional>\n";
            ret += "#include \"samal_runtime.hpp\"\n";
        } else {
            ret += '#include "${node.getName()}.hpp"\n';
            ret += "\n";
            // used datatypes
            final alreadyDeclared = [];
            for(d in node.getUsedDatatypes()) {
                ret += d.toCppGCTypeDeclaration(alreadyDeclared);
            }
        }
        ret += "\n";
        ret += node.getDeclarations().map((decl) -> (decl.toSrc(this, ctx))).join("\n\n");
        ret += "\n";
        return ret;
    }
    public function makeScopeNode(ctx : SourceCreationContext, node : CppScopeNode) : String {
        return "{\n" + node.getStatements().map((stmt) -> stmt.toSrc(this, ctx.next()) + ";\n").join("") + indent(ctx.prev()) + "}";
    }    
    public function makeFunctionDeclaration(ctx : SourceCreationContext, node : CppFunctionDeclaration) : String {
        final paramsAsStrArray = node.getParams().map((p) -> '${p.getDatatype().toCppType()} ${p.getName()}');
        var ret = node.getDatatype().getReturnType().toCppType() + " " + node.getMangledName() + "(" 
            + ["samalrt::SamalContext &$ctx"].concat(paramsAsStrArray).join(", ") + ")";

        final cppCtx = Std.downcast(ctx, CppContext);
        if(cppCtx.isHeader()) {
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
        final cppCtx = Std.downcast(ctx, CppContext);
        if(cppCtx.isSource()) {
            return "";
        }
        return "struct " + node.getMangledName() + " {\n"
            + node.getFields().map(function(f) {
                return " " + f.getDatatype().toCppType() + " " + f.getName() + ";\n";
            }).join("")
            + "};";
    }
    public function makeScopeStatement(ctx : SourceCreationContext, node : CppScopeStatement) : String {
        return indent(ctx) + node.getScope().toSrc(this, ctx.next());
    }    
    public function makeBinaryExprStatement(ctx : SourceCreationContext, node : CppBinaryExprStatement) : String {
        return indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = " + node.getLhsVarName() + " " + node.opAsStr() + " " + node.getRhsVarName() + getTrackerString(node);
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
    public function makeCreateLambdaStatement(ctx : SourceCreationContext, node : CppCreateLambdaStatement) : String {
        final bufferVarName = "buffer$$$" + Util.getUniqueId();
        // first the lambda itself
        var ret = 
            indent(ctx) + node.getDatatype().toCppType() + " " + node.getVarName() + " = *[](samalrt::SamalContext& $ctx, "
            + node.getParams().map(function(p) return p.getDatatype().toCppType() + " " + p.getName()).join(", ") + ") -> " + node.getDatatype().getReturnType().toCppType() + " {\n"
            + indent(ctx.next()) + "uint8_t* " + bufferVarName + " = (uint8_t*)$ctx.getLambdaCapturedVarPtr() + sizeof(void*);\n"
            + node.getCapturedVariables().map(function(p) {
                return 
                    indent(ctx.next()) + p.getDatatype().toCppType() + " " + p.getName() + ";\n"
                    + indent(ctx.next()) + "memcpy(&" + p.getName() + ", " + bufferVarName + ", " + p.getDatatype().toCppGCTypeStr() + ".getSizeOnStack());\n"
                    + indent(ctx.next()) + bufferVarName + " += " + p.getDatatype().toCppGCTypeStr() + ".getSizeOnStack();\n";
            }).join("")
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
    public function makeTailCallSelf(ctx : SourceCreationContext, node : CppTailCallSelf) : String {
        var ret = "";
        for(param in node.getParams()) {
            ret += indent(ctx) + param.paramName + " = " + param.paramValue + ";\n";
        }
        ret += indent(ctx) + "continue";
        return ret;
    }
}