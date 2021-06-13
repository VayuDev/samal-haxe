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
    public function isStatementsEmpty() : Bool {
        return mStatements.length == 0;
    }
    public function getLastStatement() : CppStatement {
        return mStatements[mStatements.length - 1];
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

abstract class CppStatement extends CppASTNode {
    var mVarName : String;
    var mDatatype : Datatype;
    public function new(sourceRef : SourceCodeRef, datatype: Datatype, varName : String) {
        super(sourceRef);
        mVarName = varName;
        mDatatype = datatype;
    }
    public function getVarName() {
        return mVarName;
    }
}

class CppScopeStatement extends CppStatement {
    var mScope : CppScopeNode;
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, varName : String) {
        super(sourceRef, datatype, varName);
        mScope = new CppScopeNode(sourceRef);
    }
    public function getScope() {
        return mScope;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mScope = cast(mScope.replace(preorder, postorder), CppScopeNode);
    }
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
    var mOp : CppNumericMathOp;
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, resultVarName : String, lhsVarName : String, op : CppNumericMathOp, rhsVarName : String) {
        super(sourceRef, datatype, resultVarName);
        mLhsVarName = lhsVarName;
        mRhsVarName = rhsVarName;
        mOp = op;
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ": " + mVarName + " = " + mLhsVarName + " " + mOp + " " + mRhsVarName;
    }
}

enum CppAssignmentType {
    JustDeclare;
    JustAssign;
    DeclareAndAssign;
}

class CppAssignmentStatement extends CppStatement {
    var mRhsVarName : String;
    var mType : CppAssignmentType;
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, resultVarName : String, rhsVarName : String, type : CppAssignmentType) {
        super(sourceRef, datatype, resultVarName);
        mRhsVarName = rhsVarName;
        mType = type;
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ": " + mVarName + " = " + mRhsVarName + " (" + mType + ")";
    }
}

class CppSimpleLiteral extends CppStatement {
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, value : String) {
        super(sourceRef, datatype, value);
    }
}

class CppReturnStatement extends CppStatement {
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, varName : String) {
        super(sourceRef, datatype, varName);
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ": " + mVarName;
    }
}