package samal.targets;
import samal.Pipeline.TargetType;
import samal.CppAST;
import samal.targets.LanguageTarget;
using samal.Datatype.DatatypeHelpers;
using samal.Util.NullTools;

class JSContext extends SourceCreationContext {

    public function new(indent : Int, mainFunction : String) {
        super(indent, mainFunction);
    }
    public override function next() : JSContext {
        return new JSContext(mIndent + 1, mMainFunction);
    }
    public override function prev() : JSContext {
        return new JSContext(mIndent - 1, mMainFunction);
    }
}

class JSTarget extends LanguageTarget {
    public function new() {}

    public function getNewContext(mainFunction : String, executionType : TargetType) {
        return new JSContext(0, mainFunction);
    }

    public function getLiteralInt(value : Int) : String {
        return Std.string(value);
    }
    public function getLiteralEmptyList() : String {
        return "null";
    }
    public function makeFile(ctx : SourceCreationContext, node : CppFile) : String {
        var ret = "";
        final jsContext = Std.downcast(ctx, JSContext);
        ret += node.getDeclarations().map((decl) -> (decl.toSrc(this, ctx))).join("\n\n");
        ret += "\n";
        return ret;
    }
    public function makeScopeNode(ctx : SourceCreationContext, node : CppScopeNode) : String {
        return "{\n" + node.getStatements().map((stmt) -> stmt.toSrc(this, ctx.next()) + ";\n").join("") + indent(ctx.prev()) + "}";
    }    
    public function makeFunctionDeclaration(ctx : SourceCreationContext, node : CppFunctionDeclaration) : String {
        final paramsAsStrArray = node.getParams().map((p) -> '${p.getName()}');
        var ret = "function " + node.getMangledName() + "(" 
            + ["$ctx"].concat(paramsAsStrArray).join(", ") + ")";

        ret += node.getBody().toSrc(this, ctx.next());
        ret += "\n";
        if(node.getMangledName() == ctx.getMainFunctionMangledName()) {
            ret += 'console.log(${node.getMangledName()}(new samalrt.SamalContext()));';
        }
        ret += "\n";
        
        return ret;
    }
    public function makeScopeStatement(ctx : SourceCreationContext, node : CppScopeStatement) : String {
        return indent(ctx) + node.getScope().toSrc(this, ctx.next());
    }    
    public function makeBinaryExprStatement(ctx : SourceCreationContext, node : CppBinaryExprStatement) : String {
        return indent(ctx) + "let " + node.getVarName() + " = " + node.getLhsVarName() + " " + node.opAsStr() + " " + node.getRhsVarName();
    }    
    public function makeUnaryExprStatement(ctx : SourceCreationContext, node : CppUnaryExprStatement) : String {
        final ret = indent(ctx) + "let " + node.getVarName();
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
    public function makeCreateLambdaStatement(ctx : SourceCreationContext, node : CppCreateLambdaStatement) : String {
        final paramsStr = ["$ctx"].concat(node.getParams().map(function(p) return p.getName())).join(", ");
        return indent(ctx) + "let " + node.getVarName() + " = function(" + paramsStr + ")" + node.getBody().toSrc(this, ctx.next());
    }
}