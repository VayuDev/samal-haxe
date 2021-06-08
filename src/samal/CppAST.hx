package samal;

import samal.AST;
import samal.Tokenizer.SourceCodeRef;

class CppASTNode extends ASTNode {
    public function new(sourceRef : SourceCodeRef) {
        super(sourceRef);
    }
}
class CppFile extends CppASTNode {
    var mDeclarations : Array<CppDeclaration>;
    public function new(sourceRef : SourceCodeRef, declarations : Array<CppDeclaration>) {
        super(sourceRef);
        mDeclarations = declarations;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mDeclarations = Util.replaceNodes(mDeclarations, preorder, postorder);
    }
}

class CppScopeNode extends CppASTNode {
    var mStatements : Array<CppStatement> = [];
    public function addStatement(stmt : CppStatement) {
        mStatements.push(stmt);
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mStatements = Util.replaceNodes(mStatements, preorder, postorder);
    }
}

class CppDeclaration extends CppASTNode {

}

class CppFunctionDeclaration extends CppDeclaration {
    var mDatatype : Datatype;
    var mMangledName : String;
    var mParams : Array<NamedAndTypedParameter>;
    var mBody : CppScopeNode;
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, mangledName : String, params : Array<NamedAndTypedParameter>, body : CppScopeNode) {
        super(sourceRef);
        mDatatype = datatype;
        mMangledName = mangledName;
        mParams = params;
        mBody = body;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mBody = cast(mBody.replace(preorder, postorder), CppScopeNode);
    }
}

class CppStatement extends CppASTNode {

}

enum CppNumericMathOp {
    Add;
    Sub;
    Mul;
    Div;
}

class CppNumericMathStatement extends CppStatement {
    var mLhsVarName : String;
    var mRhsVarName : String;
    var mResultVarName : String;
    var mOp : CppNumericMathOp;
    public function new(sourceRef : SourceCodeRef, resultVarName : String, lhsVarName : String, op : CppNumericMathOp, rhsVarName : String) {
        super(sourceRef);
        mLhsVarName = lhsVarName;
        mRhsVarName = rhsVarName;
        mResultVarName = resultVarName;
        mOp = op;
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ": " + mResultVarName + " = " + mLhsVarName + " " + mOp + " " + mRhsVarName;
    }
}