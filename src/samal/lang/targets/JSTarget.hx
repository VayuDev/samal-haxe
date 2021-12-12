package samal.lang.targets;
import samal.lang.Program.CppProgram;
import samal.lang.Pipeline.TargetType;
import samal.lang.CppAST;
import samal.lang.targets.LanguageTarget;
using samal.lang.Datatype.DatatypeHelpers;
using samal.lang.Util.NullTools;

enum DeclareDatatypesOrFunctions {
    Datatypes;
    Functions;
}

class JSContext extends SourceCreationContext {
    final mDof : DeclareDatatypesOrFunctions;
    final mProgram : CppProgram;

    public function new(indent : Int, mainFunction : String, dof : DeclareDatatypesOrFunctions, program : CppProgram) {
        super(indent, mainFunction);
        mDof = dof;
        mProgram = program;
    }
    public override function next() : JSContext {
        return new JSContext(mIndent + 1, mMainFunction, mDof, mProgram);
    }
    public override function prev() : JSContext {
        return new JSContext(mIndent - 1, mMainFunction, mDof, mProgram);
    }
    public function getDof() {
        return mDof;
    }
    public function getProgram() {
        return mProgram;
    }
}

class JSTarget extends LanguageTarget {
    public function new() {}

    public function getLiteralBool(value : Bool) : String {
        return value ? "true" : "false";
    }
    public function getLiteralByte(value : Int) : String {
        return Std.string(value);
    }
    public function getLiteralChar(value : String) : String {
        if(value.charCodeAt(0).sure() < 20) {
            return "'\\u" + value.charCodeAt(0).sure() + "'";
        }
        return "'" + value + "'";
    }
    public function getLiteralInt(value : Int) : String {
        return Std.string(value);
    }
    public function getLiteralEmptyList(baseType : Datatype) : String {
        return "null";
    }
    public function makeFile(ctx : SourceCreationContext, node : CppFile) : String {
        var ret = "";
        final jsContext = Std.downcast(ctx, JSContext);
        ret += node.getDeclarations().map((decl) -> (decl.toSrc(this, ctx))).filter(function(d) return d != "").join("\n\n");
        ret += "\n";
        return ret;
    }
    public function makeScopeNode(ctx : SourceCreationContext, node : CppScopeNode) : String {
        return "{\n" + node.getStatements().map((stmt) -> stmt.toSrc(this, ctx.next()) + ";\n").join("") + indent(ctx.prev()) + "}";
    }    
    public function makeFunctionDeclaration(ctx : SourceCreationContext, node : CppFunctionDeclaration) : String {
        if(Std.downcast(ctx, JSContext).getDof() == Datatypes)
            return "";
        final paramsAsStrArray = node.getParams().map((p) -> '${p.getName()}');
        var ret = "function " + node.getMangledName() + "(" 
            + ["$ctx"].concat(paramsAsStrArray).join(", ") + ") {\n";

        ret += indent(ctx.next()) + "while(true) ";
        ret += node.getBody().toSrc(this, ctx.next().next());

        ret += indent(ctx) + "\n}";

        if(node.getMangledName() == ctx.getMainFunctionMangledName()) {
            ret += '\nconsole.log(${node.getMangledName()}(new samalrt.SamalContext()));\n';
        }
        
        return ret;
    }
    public function makeStructDeclaration(ctx : SourceCreationContext, node : CppStructDeclaration) : String {
        if(cast(ctx, JSContext).getDof() != Datatypes)
            return "";
        final thisTypeName = node.getDatatype().getUsertypeMangledName();
        return "class " + thisTypeName + " {\n" 
            + " constructor(" + node.getFields().map(function(f) return f.getFieldName()).join(",") + ") {\n"
            + node.getFields().map(function(f) {
                return "  this." + f.getFieldName() + " = " + f.getFieldName() + ";\n";
            }).join("")
            + " }\n"
            + " equals(other) {\n"
            // This check isn't actually necessary as it is (should be?) check by stage 2 and no longer needed at runtime.
            // It might be useful in case some is interacting with samal code from the outside? Maybe we should make it optional?
            //+ "  if (!(other instanceof " + thisTypeName + ")) return false;\n"
            + node.getFields().map(function(f) {
                return "  if(!" + genCheckIfEqualCode("this." + f.getFieldName(), "other." + f.getFieldName(), f.getDatatype()) + ") return false;";
            }).join("")
            + "  return true;"
            + " }\n"
            + "}";
    }
    public function makeEnumDeclaration(ctx : SourceCreationContext, node : CppEnumDeclaration) : String {
        if(cast(ctx, JSContext).getDof() != Datatypes)
            return "";
        final memberIndexList = Util.seq(node.getLargestVariantSize());
        return "class " + node.getDatatype().getUsertypeMangledName() + " {\n"
            + " constructor(variant, " + memberIndexList.map(function(i) {return "p" + i;}).join(", ") + ") {\n"
            + "  this.variant = variant;\n"
            + memberIndexList.map(function(i) {
                return "  this.m" + i + " = p" + i + ";\n";
            }).join("")
            + " }\n"
            + " equals(other) {\n"
            + "  if(this.variant !== other.variant) return false;\n"
            + memberIndexList.map(function(i) {
                final lhsVarName = "this.m" + i;
                final rhsVarName = "other.m" + i;
                /*  This is actually a bit funky because even after the .equals check fails, we still check for equality with ===.
                    As everything is immutable in samal, this shouldn't be a problem though.
                */
                return "  if (!(" 
                    + "(" + lhsVarName + " === null && " + rhsVarName + " === null) || "
                    + "(" + lhsVarName + " === undefined && " + rhsVarName + " === undefined) || "
                    + "((" + lhsVarName + ".equals !== undefined && " + lhsVarName + ".equals(" + rhsVarName + "))"
                    + " || " + lhsVarName + " === " + rhsVarName + "))) return false;\n";
            }).join("")
            + "  return true;"
            + " }\n"
            + "}";
    }
    public function makeScopeStatement(ctx : SourceCreationContext, node : CppScopeStatement) : String {
        return indent(ctx) + node.getScope().toSrc(this, ctx.next());
    }
    public function makeBinaryExprStatement(ctx : SourceCreationContext, node : CppBinaryExprStatement) : String {
        var opStr : String = "";
        switch(node.getOp()) {
            case Equal, NotEqual:
                return indent(ctx) + "let " + node.getVarName() + " = " + (node.getOp() == NotEqual ? "!" : "") 
                    + genCheckIfEqualCode(node.getLhsVarName(), node.getRhsVarName(), node.getLhsAndRhsDatatype());
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
        return indent(ctx) + "let " + node.getVarName() + " = " + node.getLhsVarName() + " " + opStr + " " + node.getRhsVarName();
    }
    public function makeUnaryExprStatement(ctx : SourceCreationContext, node : CppUnaryExprStatement) : String {
        var ret = indent(ctx) + "let " + node.getVarName();
        switch(node.getOp()) {
            case Not:
                ret += " = !(" + node.getExpr() + ")";
            case ListGetHead:
                ret += " = (" + node.getExpr() + ").value";
            case ListGetTail:
                ret += " = (" + node.getExpr() + ").next";
            case ListIsEmpty:
                ret += " = (" + node.getExpr() + ") === null";
        }
        return ret;
    }
    public function makeUnreachable(ctx : SourceCreationContext, node : CppUnreachable) : String {
        return indent(ctx) + " assert(false)";
    }
    public function makeAssignmentStatement(ctx : SourceCreationContext, node : CppAssignmentStatement) : String {
        switch(node.getType()) {
            case JustDeclare:
                return indent(ctx) + "let " + node.getVarName() + " = undefined";
            case JustAssign:
                return indent(ctx) + node.getVarName() + " = " + node.getRhsVarName();
            case DeclareAndAssign:
                return indent(ctx) + "let " + node.getVarName() +  " = " + node.getRhsVarName();
        }
    }    
    public function makeReturnStatement(ctx : SourceCreationContext, node : CppReturnStatement) : String {
        return indent(ctx) + "return " + node.getVarName();
    }
    public function makeFunctionCallStatement(ctx : SourceCreationContext, node : CppFunctionCallStatement) : String {
        return indent(ctx) + "let " + node.getVarName() + " = " + node.getFunctionName() + "(" + ["$ctx"].concat(node.getParams()).join(", ") + ")";
    }
    public function makeIfStatement(ctx : SourceCreationContext, node : CppIfStatement) : String {
        return indent(ctx) + "if (" + node.getConditionVarName() + ") " + node.getMainBody().toSrc(this, ctx.next()) + " else " + node.getElseBody().toSrc(this, ctx.next());
    }
    public function makeListPrependStatement(ctx : SourceCreationContext, node : CppListPrependStatement) : String {
        return indent(ctx) + "let " + node.getVarName() + " = new samalrt.List(" + node.getValue() + ", " + node.getList() + ")";
    }
    public function makeCreateEnumStatement(ctx : SourceCreationContext, node : CppCreateEnumStatement) : String {
        final jsCtx = cast(ctx, JSContext);
        final decl = cast(jsCtx.getProgram().findUsertypeDeclaration(node.getDatatype()), CppEnumDeclaration);
        final choseenVariant = Util.findEnumVariant(decl.getVariants(), node.getVariantName());
        return indent(ctx) + "let " + node.getVarName() + " = new " + node.getDatatype().getUsertypeMangledName() + "(" 
            + choseenVariant.index + ", " + node.getParams().map(function(p) return p.value).join(", ") + ")";
    }
    public function makeCreateLambdaStatement(ctx : SourceCreationContext, node : CppCreateLambdaStatement) : String {
        final paramsStr = ["$ctx"].concat(node.getParams().map(function(p) return p.getName())).join(", ");
        return indent(ctx) + "let " + node.getVarName() + " = function(" + paramsStr + ")" + node.getBody().toSrc(this, ctx.next());
    }
    public function makeCreateStructStatement(ctx : SourceCreationContext, node : CppCreateStructStatement) : String {
        final paramsStr = node.getParams().map(function(p) return p.value).join(", ");
        return indent(ctx) + "let " + node.getVarName() + " = new " + node.getDatatype().getUsertypeMangledName() + "(" + paramsStr + ")";
    }
    public function makeCreateTupleStatement(ctx : SourceCreationContext, node : CppCreateTupleStatement) : String {
        return indent(ctx) + "let " + node.getVarName() + " = [" + node.getParams().join(", ") + "]";
    }
    public function makeEnumIsVariantStatement(ctx : SourceCreationContext, node : CppEnumIsVariantStatement) : String {
        return indent(ctx) + "let " + node.getVarName() + " = " + node.getEnumExpr() + ".variant == " + node.getVariantIndex();
    }
    public function makeFetchEnumFieldStatement(ctx : SourceCreationContext, node : CppFetchEnumFieldStatement) : String {
        return indent(ctx) + "let " + node.getVarName() + " = " + node.getEnumExpr() + ".m" + node.getFieldIndex();
    }
    public function makeTailCallSelf(ctx : SourceCreationContext, node : CppTailCallSelf) : String {
        var ret = "";
        for(param in node.getParams()) {
            ret += indent(ctx) + param.paramName + " = " + param.paramValue + ";\n";
        }
        ret += indent(ctx) + "continue";
        return ret;
    }

    private function genCheckIfEqualCode(lhsVarName : String, rhsVarName : String, datatype : Datatype) : String {
        if(datatype.isContainerType()) {
            return "((" + lhsVarName + " === null && " + rhsVarName + " === null) || " + lhsVarName + ".equals(" + rhsVarName + "))";
        }
        return "(" + lhsVarName + " === " + rhsVarName + ")";
    }
}