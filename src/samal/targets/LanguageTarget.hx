package samal.targets;

import samal.CppAST;
import samal.AST;

class SourceCreationContext {
    var mIndent = 0;
    var mMainFunction : String;

    public function new(indent : Int, mainFunction : String) {
        mIndent = indent;
        mMainFunction = mainFunction;
    }
    public function getIndent() {
        return mIndent;
    }
    public function next() : SourceCreationContext {
        return new SourceCreationContext(mIndent + 1, mMainFunction);
    }
    public function prev() : SourceCreationContext {
        return new SourceCreationContext(mIndent - 1, mMainFunction);
    }
    public function getMainFunctionMangledName() {
        return mMainFunction;
    }
}

abstract class LanguageTarget {

    abstract public function getLiteralInt(value : Int) : String;
    abstract public function getLiteralEmptyList() : String;
    function indent(ctx : SourceCreationContext) : String {
        return Util.createIndentStr(ctx.getIndent());
    }
    public function makeDefault(ctx : SourceCreationContext, node : CppASTNode) : String {
        return indent(ctx) + "UNKNOWN";
    }
    abstract public function makeFile(ctx : SourceCreationContext, node : CppFile) : String;
    abstract public function makeScopeNode(ctx : SourceCreationContext, node : CppScopeNode) : String;
    abstract public function makeFunctionDeclaration(ctx : SourceCreationContext, node : CppFunctionDeclaration) : String;
    abstract public function makeScopeStatement(ctx : SourceCreationContext, node : CppScopeStatement) : String;
    abstract public function makeBinaryExprStatement(ctx : SourceCreationContext, node : CppBinaryExprStatement) : String;
    abstract public function makeUnaryExprStatement(ctx : SourceCreationContext, node : CppUnaryExprStatement) : String;
    abstract public function makeUnreachable(ctx : SourceCreationContext, node : CppUnreachable) : String;
    abstract public function makeAssignmentStatement(ctx : SourceCreationContext, node : CppAssignmentStatement) : String;
    abstract public function makeReturnStatement(ctx : SourceCreationContext, node : CppReturnStatement) : String;
    abstract public function makeFunctionCallStatement(ctx : SourceCreationContext, node : CppFunctionCallStatement) : String;
    abstract public function makeIfStatement(ctx : SourceCreationContext, node : CppIfStatement) : String;
    abstract public function makeListPrependStatement(ctx : SourceCreationContext, node : CppListPrependStatement) : String;
    abstract public function makeCreateLambdaStatement(ctx : SourceCreationContext, node : CppCreateLambdaStatement) : String;
    abstract public function makeTailCallSelf(ctx : SourceCreationContext, node : CppTailCallSelf) : String;
}


