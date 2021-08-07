package samal;

import samal.Program;
import samal.SamalAST;
import samal.AST;
import samal.Datatype;
using samal.Util.NullTools;
using samal.Datatype.DatatypeHelpers;
import haxe.Exception;
import samal.Tokenizer.SourceCodeRef;
import cloner.Cloner;

typedef InstantiatedUserType = {originalTemplatedType : Datatype, passedTemplateParams : Array<Datatype>}

class StringToDatatypeMapperUsingSamalProgram extends StringToDatatypeMapper {
    final mProgram : SamalProgram;
    final mModuleScope : String;
    final mInstantiatedUserTypesOut : Map<String, InstantiatedUserType>;
    public function new(program : SamalProgram, moduleScope : String, instantiatedTypesOut : Map<String, InstantiatedUserType>) {
        mProgram = program;
        mModuleScope = moduleScope;
        mInstantiatedUserTypesOut = instantiatedTypesOut;
    }
    public function getDatatype(name : String, templateParams : Array<Datatype>) : Datatype {
        final value = mProgram.findDatatype(name, mModuleScope).getDatatype();
        switch(value.sure()) {
            case Struct(structName, _):
                final retType = Datatype.Struct(structName, templateParams);
                mInstantiatedUserTypesOut.set(retType.getStructMangledName(), {originalTemplatedType: value, passedTemplateParams: templateParams});
                return retType;
            default:
                return value.sure();
        }
    }
    public function getInstantiatedUserTypes() {
        return mInstantiatedUserTypesOut;
    }
}

class Stage1 {
    var mProgram : SamalProgram;
    var mCurrentModule : String = "";
    // maps mangled type name to instantiation info
    var mInstantiatedUserTypes : Map<String, InstantiatedUserType> = new Map<String, InstantiatedUserType>();
    var mCloner = new Cloner();

    public function new(prog : SamalProgram) {
        mProgram = prog;
    }

    public function makeStringToDatatypeMapper(moduleScope : String) : StringToDatatypeMapperUsingSamalProgram {
        return new StringToDatatypeMapperUsingSamalProgram(mProgram, moduleScope, mInstantiatedUserTypes);
    }

    private function complete(datatype : Datatype) : Datatype {
        return datatype.complete(makeStringToDatatypeMapper(mCurrentModule));
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
                    if(Std.downcast(astNode, SamalDeclarationNode) != null) {
                        var node = Std.downcast(astNode, SamalDeclarationNode);
                        node.completeWithUserTypeMap(makeStringToDatatypeMapper(mCurrentModule));
    
                    } else if(Std.downcast(astNode, SamalCreateListExpression) != null) {
                        var node = Std.downcast(astNode, SamalCreateListExpression);
                        if(node.getDatatype() != null) {
                            node.setDatatype(complete(node.getDatatype().sure()));
                        }

                    } else if(Std.downcast(astNode, SamalCreateLambdaExpression) != null) {
                        var node = Std.downcast(astNode, SamalCreateLambdaExpression);
                        node.setDatatype(complete(node.getDatatype().sure()));
                        
                    } else if(Std.downcast(astNode, SamalCreateStructExpression) != null) {
                        var node = Std.downcast(astNode, SamalCreateStructExpression);
                        node.setDatatype(complete(node.getDatatype().sure()));
                        
                    } else if(Std.downcast(astNode, SamalLoadIdentifierExpression) != null) {
                        var node = Std.downcast(astNode, SamalLoadIdentifierExpression);
                        final newTemplateParams = node.getIdentifier().getTemplateParams().map(function(param) {
                            return param.complete(makeStringToDatatypeMapper(mCurrentModule));
                        });
                        node.setIdentifier(new IdentifierWithTemplate(node.getIdentifier().getName(), newTemplateParams));
                    }
                } catch(e : DatatypeNotFound) {
                    // no need to worry (yet) as the datatype might be a template parameter
                }
            });
        });

        // step 3: instantiate template structs
        final structs = [];
        trace(mInstantiatedUserTypes);
        for(entry in mInstantiatedUserTypes) {
            final decl = mProgram.findDatatypeDeclaration(entry.originalTemplatedType);
            if(decl.getDatatype().isComplete())
                continue;

            final newDecl = decl.cloneWithTemplateParams(
                new StringToDatatypeMapperUsingTypeMap(Util.buildTemplateReplacementMap(decl.getTemplateParams(), entry.passedTemplateParams)), 
                entry.passedTemplateParams,
                mCloner);
            structs.push(newDecl);
        }
        mProgram.addModule(new SamalModuleNode(new SourceCodeRef(0, 0, 0, 0, 0, 0, ""), "$templates", structs));
        return mProgram;
    }
}