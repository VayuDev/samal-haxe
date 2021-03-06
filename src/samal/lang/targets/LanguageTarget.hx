package samal.lang.targets;

import samal.lang.CppAST;
import samal.lang.AST;

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

    abstract public function getLiteralBool(value : Bool) : String;
    abstract public function getLiteralByte(value : Int) : String;
    abstract public function getLiteralChar(value : String) : String;
    abstract public function getLiteralInt(value : Int) : String;
    abstract public function getLiteralEmptyList(baseType : Datatype) : String;
    function indent(ctx : SourceCreationContext) : String {
        return Util.createIndentStr(ctx.getIndent());
    }
    public function makeDefault(ctx : SourceCreationContext, node : CppASTNode) : String {
        return indent(ctx) + "UNKNOWN";
    }
    abstract public function makeFile(ctx : SourceCreationContext, node : CppFile) : String;
    abstract public function makeScopeNode(ctx : SourceCreationContext, node : CppScopeNode) : String;
    abstract public function makeFunctionDeclaration(ctx : SourceCreationContext, node : CppFunctionDeclaration) : String;
    abstract public function makeEnumDeclaration(ctx : SourceCreationContext, node : CppEnumDeclaration) : String;
    abstract public function makeStructDeclaration(ctx : SourceCreationContext, node : CppStructDeclaration) : String;
    abstract public function makeAssignmentStatement(ctx : SourceCreationContext, node : CppAssignmentStatement) : String;
    abstract public function makeBinaryExprStatement(ctx : SourceCreationContext, node : CppBinaryExprStatement) : String;
    abstract public function makeCreateEnumStatement(ctx : SourceCreationContext, node : CppCreateEnumStatement) : String;
    abstract public function makeCreateLambdaStatement(ctx : SourceCreationContext, node : CppCreateLambdaStatement) : String;
    abstract public function makeCreateStructStatement(ctx : SourceCreationContext, node : CppCreateStructStatement) : String;
    abstract public function makeCreateTupleStatement(ctx : SourceCreationContext, node : CppCreateTupleStatement) : String;
    abstract public function makeEnumIsVariantStatement(ctx : SourceCreationContext, node : CppEnumIsVariantStatement) : String;
    abstract public function makeFetchEnumFieldStatement(ctx : SourceCreationContext, node : CppFetchEnumFieldStatement) : String;
    abstract public function makeFunctionCallStatement(ctx : SourceCreationContext, node : CppFunctionCallStatement) : String;
    abstract public function makeIfStatement(ctx : SourceCreationContext, node : CppIfStatement) : String;
    abstract public function makeListPrependStatement(ctx : SourceCreationContext, node : CppListPrependStatement) : String;
    abstract public function makeNativeStatement(ctx : SourceCreationContext, node : CppNativeStatement) : String;
    abstract public function makeReturnStatement(ctx : SourceCreationContext, node : CppReturnStatement) : String;
    abstract public function makeScopeStatement(ctx : SourceCreationContext, node : CppScopeStatement) : String;
    abstract public function makeTailCallSelf(ctx : SourceCreationContext, node : CppTailCallSelf) : String;
    abstract public function makeUnaryExprStatement(ctx : SourceCreationContext, node : CppUnaryExprStatement) : String;
    abstract public function makeUnreachable(ctx : SourceCreationContext, node : CppUnreachable) : String;
}


