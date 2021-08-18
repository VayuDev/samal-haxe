package samal.lang;

import samal.lang.Util.Cloneable;
import haxe.Exception;
import samal.lang.generated.SamalAST.SamalExpression;
import samal.bootstrap.Tokenizer.SourceCodeRef;
import samal.lang.Util;

class ASTNode implements Cloneable {
    var mSourceCodeRef : SourceCodeRef;
    function new(sourceRef : SourceCodeRef) {
        this.mSourceCodeRef = sourceRef;
    }


    public function dump() : String {
        var indent = 0;
        var ret = dumpSelf() + "\n";
        replaceChildren(function(node) {
            indent += 1;
            ret += Util.createIndentStr(indent) + node.dumpSelf() + "\n";
            return node;
        },
        function(node : ASTNode) {
            indent -= 1;
            return node;
        });
        return ret;
    }
    public function dumpSelf() {
        return Type.getClassName(Type.getClass(this));
    }
    public function travserePostorder(postorder : (ASTNode) -> Void) {
        traverse(function(childNode) {
        }, function(childNode) {
            postorder(childNode);
        });
    }
    public function traverse(preorder : (ASTNode) -> Void, postorder : (ASTNode) -> Void) {
        replace(function(childNode) {
            preorder(childNode);
            return childNode;
        }, function(childNode) {
            postorder(childNode);
            return childNode;
        });
    }
    public function replace(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) : ASTNode {
        var self = preorder(this);
        self.replaceChildren(preorder, postorder);
        return postorder(self);
    }
    public function replaceChildren(preorder : (ASTNode) -> ASTNode, postorder : (ASTNode) -> ASTNode) {
    }

    public function errorInfo() : String {
        return mSourceCodeRef.errorInfo() + ": ";
    }
    public function getSourceRef() {
        return mSourceCodeRef;
    }
    public function clone() : ASTNode {
        throw new Exception("Clone not implemented for " + Type.getClassName(Type.getClass(this)));
    }
}