package samal;

import haxe.Int32;
import samal.Tokenizer.SourceCodeRef;
import samal.AST;
import samal.Util;

class SamalASTNode extends ASTNode {
    public function new(sourceRef : SourceCodeRef) {
        super(sourceRef);
    }
}

class SamalModuleNode extends SamalASTNode {
    var mDeclarations : Array<SamalDeclarationNode>;
    public function new(sourceRef : SourceCodeRef, declarations : Array<SamalDeclarationNode>) {
        super(sourceRef);
        mDeclarations = declarations;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mDeclarations = Util.replaceNodes(mDeclarations, preorder, postorder);
    }
}

class SamalDeclarationNode extends SamalASTNode {

}

class SamalFunctionDeclarationNode extends SamalDeclarationNode {
    var mName : IdentifierWithTemplate;
    var mParams : Array<NamedAndTypedParameter>;
    var mReturnType : Datatype;
    var mBody : SamalScopeExpression;
    public function new(sourceRef : SourceCodeRef, name : IdentifierWithTemplate, params : Array<NamedAndTypedParameter>, returnType : Datatype, body : SamalScopeExpression) {
        super(sourceRef);
        this.mName = name;
        this.mParams = params;
        this.mReturnType = returnType;
        this.mBody = body;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mBody = cast(mBody.replace(preorder, postorder), SamalScopeExpression);
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + " " + mName.dump() + " " + getDatatype();
    }
    public function getDatatype() : Datatype {
        return Datatype.Function(mReturnType, mParams.map(function(p) {return p.getDatatype();}));
    }
}

class SamalStatement extends SamalASTNode {

}

class SamalExpression extends SamalStatement {
    var mDatatype : Null<Datatype>;

    public override function dumpSelf() : String {
        if(mDatatype == null) {
            return super.dumpSelf() + " ()";
        } else {
            return super.dumpSelf() + " (" + NullTools.sure(mDatatype) + ")";
        }
    }
}

class SamalLiteralIntExpression extends SamalExpression {
    var mVal : Int32;
    public function new(sourceRef : SourceCodeRef, val : Int32) {
        super(sourceRef);
        mVal = val;
    }
    public override function dumpSelf() : String {
        return super.dumpSelf() + ": " + mVal;
    }
}

class SamalScopeExpression extends SamalExpression {
    var mStatements : Array<SamalStatement>;
    public function new(sourceRef : SourceCodeRef, statements : Array<SamalStatement>) {
        super(sourceRef);
        mStatements = statements;
    }
    public override function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
        mStatements = Util.replaceNodes(mStatements, preorder, postorder);
    }
}