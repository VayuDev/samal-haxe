package samal;

import haxe.EnumTools;
import haxe.ds.GenericStack;
import haxe.Exception;
import samal.Datatype.DatatypeHelpers;
import samal.AST;
import samal.SamalAST;
import samal.Util;
import samal.Datatype;
using samal.Util.NullTools;
using samal.Datatype.DatatypeHelpers;
import samal.Program;


class VarDeclaration {
    var mName : String;
    var mType : Datatype;
    public function new(name : String, type : Datatype) {
        mName = name;
        mType = type;
    }
    public function getIdentifier() {
        return mName;
    }
    public function getType() {
        return mType;
    }
}

class Stage2 {
    var mProgram : SamalProgram;
    var mScopeStack : GenericStack<Map<String, VarDeclaration>> = new GenericStack();
    var mCurrentModule : String = "";

    public function new(prog : SamalProgram) {
        mProgram = prog;
    }

    function preorder(astNode : ASTNode) {
        if(Std.downcast(astNode, SamalScope) != null) {
            mScopeStack.add(new Map<String, VarDeclaration>());
        } else if(Std.downcast(astNode, SamalFunctionDeclarationNode) != null) {
            mScopeStack.add(new Map<String, VarDeclaration>());
            var node = Std.downcast(astNode, SamalFunctionDeclarationNode);
            for(param in node.getParams()) {
                mScopeStack.first().sure().set(param.getName(), new VarDeclaration(param.getName(), param.getDatatype()));
            }
        }
    }

    function postorder(astNode : ASTNode) {
        if(Std.downcast(astNode, SamalScope) != null) {
            var node = Std.downcast(astNode, SamalScope);
            var stmt = node.getStatements();
            if(stmt.length == 0) {
                node.setDatatype(Datatype.Tuple([]));
            } else {
                node.setDatatype(stmt[stmt.length - 1].getDatatype().sure());
            }
            mScopeStack.pop();
        } else if(Std.downcast(astNode, SamalFunctionDeclarationNode) != null) {
            var node = Std.downcast(astNode, SamalFunctionDeclarationNode);
            final expectedReturnType = DatatypeHelpers.getReturnType(node.getDatatype());
            if(!expectedReturnType.equals(node.getBody().getDatatype().sure())) {
                throw new Exception(
                    node.errorInfo() 
                    + "Expected return type " 
                    + expectedReturnType 
                    + ", got: " 
                    + node.getBody().getDatatype().sure());
            }
            mScopeStack.pop();

        } else if(Std.downcast(astNode, SamalBinaryExpression) != null) {
            var node = Std.downcast(astNode, SamalBinaryExpression);
            final lhsType = node.getLhs().getDatatype().sure();
            final rhsType = node.getRhs().getDatatype().sure();

            if(!lhsType.equals(rhsType)) {
                if(rhsType.match(List(_)) && lhsType.equals(rhsType.getBaseType()) && node.getOperator() == Add) {
                    // list prepend
                    node.setDatatype(rhsType);
                    return;
                }
                throw new Exception('${node.errorInfo()} Lhs and rhs types aren\'t equal. Lhs is ${node.getLhs().getDatatype().sure()}, rhs is ${node.getRhs().getDatatype().sure()}');
            }
            if(!([Int].contains(lhsType))) {
                throw new Exception('${node.errorInfo()} The ${node.getOperator()} operator is only defined for integers, not for ${node.getLhs().getDatatype().sure()}');
            }
            if([Less, LessEqual, More, MoreEqual].contains(node.getOperator())) {
                node.setDatatype(Datatype.Bool);
            } else {
                node.setDatatype(lhsType);
            }

        } else if(Std.downcast(astNode, SamalAssignmentExpression) != null) {
            var node = Std.downcast(astNode, SamalAssignmentExpression);
            node.setDatatype(node.getRhs().getDatatype().sure());
            var decl : VarDeclaration;
            if(mScopeStack.first().sure().exists(node.getIdentifier())) {
                // shadowing
                // get shadow amount
                var nameStr = mScopeStack.first().sure()[node.getIdentifier()].sure().getIdentifier();
                var indexOfDollar = nameStr.lastIndexOf("$");
                var newShadowAmount : Int = 0;
                if(indexOfDollar == -1) {
                    newShadowAmount = 1;
                } else {
                    newShadowAmount = Std.parseInt(nameStr.substr(indexOfDollar + 1)).sure() + 1;
                }
                decl = new VarDeclaration(node.getIdentifier() + "$" + newShadowAmount, node.getDatatype().sure());
            } else {
                decl = new VarDeclaration(node.getIdentifier(), node.getDatatype().sure());
            }
            mScopeStack.first().sure().set(node.getIdentifier(), decl);
            node.setIdentifier(decl.getIdentifier());

        } else if(Std.downcast(astNode, SamalLoadIdentifierExpression) != null) {
            var node = Std.downcast(astNode, SamalLoadIdentifierExpression);
            if(node.getIdentifier().getTemplateParams().length == 0) {
                var decl = findIdentifier(node.getIdentifier().getName());
                node.setIdentifier(new IdentifierWithTemplate(decl.getIdentifier(), []));
                node.setDatatype(decl.getType());
            }
        } else if(Std.downcast(astNode, SamalFunctionCallExpression) != null) {
            var node = Std.downcast(astNode, SamalFunctionCallExpression);
            node.setDatatype(node.getFunction().getDatatype().sure().getReturnType());

        } else if(Std.downcast(astNode, SamalIfExpression) != null) {
            var node = Std.downcast(astNode, SamalIfExpression);

            var returnType : Null<Datatype> = null;
            for(branch in node.getAllBranches()) {
                if(returnType == null) {
                    returnType = branch.getBody().getDatatype().sure();
                } else {
                    if(returnType != branch.getBody().getDatatype().sure()) {
                        throw new Exception('${node.errorInfo()} All previous branches returend ${returnType}, but one returns ${branch.getBody().getDatatype().sure()}');
                    }
                }
                if(branch.getCondition().getDatatype().sure() != Datatype.Bool) {
                    throw new Exception('${branch.getCondition().errorInfo()} Condition must have bool-type, but has ${branch.getCondition().getDatatype().sure()}');
                }
            }
            if(node.getElse().getDatatype().sure() != returnType) {
                throw new Exception('${node.errorInfo()} All previous branches returend ${returnType}, but the else returns ${node.getElse().getDatatype().sure()}');
            }
            node.setDatatype(returnType);
        } else if(Std.downcast(astNode, SamalCreateListExpression) != null) {
            var node = Std.downcast(astNode, SamalCreateListExpression);
            if(node.getDatatype() == null) {
                var baseType : Null<Datatype> = null;
                for(child in node.getChildren()) {
                    if(baseType == null) {
                        baseType = child.getDatatype();
                    } else {
                        if(!baseType.sure().equals(child.getDatatype().sure())) {
                            throw new Exception('${node.errorInfo()} Not all initial members have the same type; previous ones are ${baseType.sure()}, but one is ${child.getDatatype().sure()}');
                        }
                    }
                }
                node.setDatatype(Datatype.List(baseType.sure()));
            }
        }
    }

    function findIdentifier(name : String) : VarDeclaration {
        // search in local scope
        var stackCopy = new GenericStack<Map<String, VarDeclaration>>();
        for(frame in mScopeStack) {
            stackCopy.add(frame);
        }
        while(!stackCopy.isEmpty()) {
            var type = stackCopy.first().sure().get(name);
            if(type != null) {
                return type;
            }
            stackCopy.pop();
        }

        // search in global scope
        var func = mProgram.findFunction(name, mCurrentModule);
        return new VarDeclaration(func.getIdentifier().mangled(), func.getDatatype());
    }

    function preorderReplace(astNode : ASTNode) : ASTNode {
        if(Std.downcast(astNode, SamalIfExpression) != null) {
            var node = Std.downcast(astNode, SamalIfExpression);
            if(node.getElseIfs().length == 0) {
                return withDatatype(node.getDatatype().sure(), new SamalSimpleIfExpression(node.getSourceRef(), node.getMainCondition(), node.getMainBody(), node.getElse()));
            }
            var currentElseIf = node.getElseIfs().shift().sure();
            var reducedIfExpr = withDatatype(
                node.getDatatype().sure(), 
                new SamalIfExpression(node.getSourceRef(), currentElseIf.getCondition(), currentElseIf.getBody(), node.getElseIfs(), node.getElse()));
            var newElseScope = new SamalScope(node.getSourceRef(), [reducedIfExpr]);
            return withDatatype(node.getDatatype().sure(), new SamalSimpleIfExpression(node.getSourceRef(), node.getMainCondition(), node.getMainBody(), newElseScope));

        } else if(Std.downcast(astNode, SamalCreateListExpression) != null) {
            var node = Std.downcast(astNode, SamalCreateListExpression);
            if(node.getChildren().length == 0) {
                return new SamalSimpleCreateEmptyList(node.getSourceRef(), node.getDatatype().sure());
            }
            var currentChild = node.getChildren().shift().sure();
            return withDatatype(
                node.getDatatype().sure(),
                new SamalSimpleListPrepend(
                    node.getSourceRef(), 
                    node.getDatatype().sure(), 
                    currentChild, 
                    new SamalCreateListExpression(node.getSourceRef(), node.getDatatype().sure().getBaseType(), node.getChildren())));

        } else if(Std.downcast(astNode, SamalBinaryExpression) != null) {
            var node = Std.downcast(astNode, SamalBinaryExpression);
            final lhsType = node.getLhs().getDatatype().sure();
            final rhsType = node.getRhs().getDatatype().sure();

            if(rhsType.match(List(_)) && lhsType.equals(rhsType.getBaseType()) && node.getOperator() == Add) {
                // list prepend
                return new SamalSimpleListPrepend(node.getSourceRef(), rhsType, node.getLhs(), node.getRhs());
            }
        }
        return astNode;
    }

    function postorderReplace(astNode : ASTNode) : ASTNode {
        return astNode;
    }

    static function withDatatype(datatype : Datatype, node : SamalExpression) : SamalExpression {
        node.setDatatype(datatype);
        return node;
    }

    public function completeDatatypes() : SamalProgram {
        mProgram.forEachModule(function (moduleName : String, ast : ASTNode) {
            mCurrentModule = moduleName;
            ast.traverse(preorder, postorder);
            ast.replace(preorderReplace, postorderReplace);
        });
        return mProgram;
    }
}