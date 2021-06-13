package samal;

import samal.AST;
import samal.Tokenizer.SourceCodeRef;

using samal.Datatype.DatatypeHelpers;

enum HeaderOrSource {
    Header;
    Source;
}

class CppContext {
    var mIndent = 0;
    var mHos : HeaderOrSource;
    public function new(indent : Int, hos : HeaderOrSource) {
        mIndent = indent;
        mHos = hos;
    }
    public function getIndent() {
        return mIndent;
    }
    public function next() {
        return new CppContext(mIndent + 1, mHos);
    }
    public function prev() {
        return new CppContext(mIndent - 1, mHos);
    }
    public function isHeader() : Bool {
        return mHos == Header;
    }
    public function isSource() : Bool {
        return mHos == Source;
    }
}

class CppASTNode extends ASTNode {
    public function new(sourceRef : SourceCodeRef) {
        super(sourceRef);
    }

    public function toCpp(ctx : CppContext) : String {
        return indent(ctx) + "UNKNOWN";
    }
    function indent(ctx : CppContext) : String {
        return Util.createIndentStr(ctx.getIndent());
    }
}
class CppFile extends CppASTNode {
    var mDeclarations : Array<CppDeclaration>;
    var mName : String;
    public function new(sourceRef : SourceCodeRef, name : String, declarations : Array<CppDeclaration>) {
        super(sourceRef);
        mDeclarations = declarations;
        mName = name;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mDeclarations = Util.replaceNodes(mDeclarations, preorder, postorder);
    }
    public override function toCpp(ctx : CppContext) : String {
        var ret = "";
        if(ctx.isHeader()) {
            ret += "#include <cstdint>\n";
            ret += "#include <cmath>\n";
        } else {
            ret += '#include "$mName.hpp"\n';
        }
        ret += "\n";
        ret += mDeclarations.map((decl) -> (decl.toCpp(ctx))).join("\n\n");
        ret += "\n";
        return ret;
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
    public override function toCpp(ctx : CppContext) : String {
        return "{\n" + mStatements.map((stmt) -> stmt.toCpp(ctx.next()) + ";\n").join("") + indent(ctx.prev()) + "}";
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

    public override function toCpp(ctx : CppContext) : String {
        var ret = mDatatype.getReturnType().toCppType() + " " + mMangledName + "(" + mParams.map((p) -> '${p.getDatatype().toCppType()} ${p.getName()}').join(",") + ")";
        if(ctx.isHeader()) {
            ret += ";";
        } else {
            ret += " " + mBody.toCpp(ctx);
        }
        return ret;
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
    public override function toCpp(ctx : CppContext) : String {
        return indent(ctx) + mScope.toCpp(ctx.next());
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
    function opAsStr() : String {
        switch(mOp) {
            case Add:
                return "+";
            case Sub:
                return "-";
            case Mul:
                return "*";
            case Div:
                return "/";
        }
    }
    public override function toCpp(ctx : CppContext) : String {
        return indent(ctx) + mDatatype.toCppType() + " " + mVarName + " = " + mLhsVarName + " " + opAsStr() + " " + mRhsVarName;
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
    public override function toCpp(ctx : CppContext) : String {
        switch(mType) {
            case JustDeclare:
                return indent(ctx) + mDatatype.toCppType() + " " + mVarName;
            case JustAssign:
                return indent(ctx) + mVarName + " = " + mRhsVarName;
            case DeclareAndAssign:
                return indent(ctx) + mDatatype.toCppType() + " " + mVarName +  " = " + mRhsVarName;
        }
    }
}

class CppSimpleLiteral extends CppStatement {
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, value : String) {
        super(sourceRef, datatype, value);
    }
    public override function toCpp(ctx : CppContext) : String {
        return mVarName;
    }
}

class CppReturnStatement extends CppStatement {
    public function new(sourceRef : SourceCodeRef, datatype : Datatype, varName : String) {
        super(sourceRef, datatype, varName);
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ": " + mVarName;
    }
    public override function toCpp(ctx : CppContext) : String {
        return indent(ctx) + "return " + mVarName;
    }
}