package samal;

import samal.Program;
import samal.SamalAST;
import samal.AST;

class Stage1 {
    var mProgram : SamalProgram;
    var mCurrentModule : String = "";
    public function new(prog : SamalProgram) {
        mProgram = prog;
    }

    public function completeGlobalIdentifiers() : SamalProgram {
        mProgram.forEachModule(function (moduleName, moduleAST) {
            mCurrentModule = moduleName;
            moduleAST.traverse(function(astNode) {

            }, function(astNode) {
                if(Std.downcast(astNode, SamalFunctionDeclarationNode) != null) {
                    var node = Std.downcast(astNode, SamalFunctionDeclarationNode);
                    node.setIdentifier(new IdentifierWithTemplate(mCurrentModule + "." + node.getIdentifier().getName(), node.getIdentifier().getTemplateParams()));

                } else if(Std.downcast(astNode, SamalStructDeclaration) != null) {
                    var node = Std.downcast(astNode, SamalStructDeclaration);
                    node.setIdentifier(new IdentifierWithTemplate(mCurrentModule + "." + node.getIdentifier().getName(), node.getIdentifier().getTemplateParams()));
                }
            });
        });
        return mProgram;
    }
}