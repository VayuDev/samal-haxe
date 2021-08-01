package samal;

import samal.Program;
import samal.SamalAST;
import samal.AST;
import samal.Datatype;
using samal.Util.NullTools;
using samal.Datatype.DatatypeHelpers;

class Stage1 {
    var mProgram : SamalProgram;
    var mCurrentModule : String = "";
    public function new(prog : SamalProgram) {
        mProgram = prog;
    }

    public function completeGlobalIdentifiers() : SamalProgram {
        // step 1: complete global identifiers
        mProgram.forEachModule(function (moduleName, moduleAST) {
            mCurrentModule = moduleName;
            moduleAST.traverse(function(astNode) {}, function(astNode) {
                if(Std.downcast(astNode, SamalFunctionDeclarationNode) != null) {
                    var node = Std.downcast(astNode, SamalFunctionDeclarationNode);
                    node.setIdentifier(new IdentifierWithTemplate(mCurrentModule + "." + node.getIdentifier().getName(), node.getIdentifier().getTemplateParams()));

                } else if(Std.downcast(astNode, SamalStructDeclaration) != null) {
                    var node = Std.downcast(astNode, SamalStructDeclaration);
                    node.setIdentifier(new IdentifierWithTemplate(mCurrentModule + "." + node.getIdentifier().getName(), node.getIdentifier().getTemplateParams()));
                
                }
            });
        });
            
        // step 2: complete datatypes
        mProgram.forEachModule(function (moduleName, moduleAST) {
            mCurrentModule = moduleName;
            moduleAST.traverse(function(astNode) {}, function(astNode) {
                try {
                    if(Std.downcast(astNode, SamalFunctionDeclarationNode) != null) {
                        var node = Std.downcast(astNode, SamalFunctionDeclarationNode);
                        node.completeWithUserTypeMap(mProgram.makeStringToDatatypeMapper(mCurrentModule));
    
                    } else if(Std.downcast(astNode, SamalCreateListExpression) != null) {
                        var node = Std.downcast(astNode, SamalCreateListExpression);
                        if(node.getDatatype() != null) {
                            node.setDatatype(node.getDatatype().sure().complete(mProgram.makeStringToDatatypeMapper(mCurrentModule)));
                        }

                    } else if(Std.downcast(astNode, SamalCreateLambdaExpression) != null) {
                        var node = Std.downcast(astNode, SamalCreateLambdaExpression);
                        node.setDatatype(node.getDatatype().sure().complete(mProgram.makeStringToDatatypeMapper(mCurrentModule)));
                        
                    } else if(Std.downcast(astNode, SamalCreateStructExpression) != null) {
                        var node = Std.downcast(astNode, SamalCreateStructExpression);
                        node.setDatatype(node.getDatatype().sure().complete(mProgram.makeStringToDatatypeMapper(mCurrentModule)));
                        
                    }
                } catch(e : DatatypeNotFound) {
                    // no need to worry (yet) as the datatype might be a template parameter
                }
            });
        });
        return mProgram;
    }
}