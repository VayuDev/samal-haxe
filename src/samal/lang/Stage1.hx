package samal.lang;

import samal.lang.Program;
import samal.lang.generated.SamalAST;
import samal.lang.AST;
import samal.lang.Datatype;
using samal.lang.Util.NullTools;
using samal.lang.Datatype.DatatypeHelpers;
import haxe.Exception;
import samal.bootstrap.Tokenizer.SourceCodeRef;

typedef InstantiatedUserType = {originalTemplatedType : Datatype, passedTemplateParams : Array<Datatype>, module : String}

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
        final decl = mProgram.findDatatypeUsingNameAndScope(name, mModuleScope);
        final value = decl.getDatatype();
        final module = decl.getName().getName().substr(0, decl.getName().getName().lastIndexOf("."));
        switch(value.sure()) {
            case Usertype(structName, _, subtype):
                final retType = Datatype.Usertype(structName, templateParams, subtype);
                mInstantiatedUserTypesOut.set(retType.getUsertypeMangledName(), {originalTemplatedType: value, passedTemplateParams: templateParams, module: module});
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
        final globalIdentifiers = new Map<String, Int>(); // Int is not used, but haxe doesn't have (native) sets
        mProgram.forEachModule(function (moduleName, moduleAST) {
            mCurrentModule = moduleName;
            moduleAST.traverse(function(astNode) {}, function(astNode) {
                if(Std.downcast(astNode, SamalDeclaration) != null) {
                    var node = Std.downcast(astNode, SamalDeclaration);
                    final name = mCurrentModule + "." + node.getName().getName();
                    if(globalIdentifiers.exists(name)) {
                        throw new Exception(astNode.errorInfo() + ": Declared twice");
                    }
                    node.setName(new IdentifierWithTemplate(name, node.getName().getTemplateParams()));
                    globalIdentifiers.set(name, 0);
                }
            });
        });
            
        // step 2: complete datatypes
        mProgram.forEachModule(function (moduleName, moduleAST) {
            mCurrentModule = moduleName;
            moduleAST.traverse(function(astNode) {}, function(astNode) {
                try {
                    if(Std.downcast(astNode, SamalDeclaration) != null) {
                        var node = Std.downcast(astNode, SamalDeclaration);
                        // this is for completing usertype parameters like structs or enums
                        node.completeWithUserTypeMap(makeStringToDatatypeMapper(mCurrentModule));
    
                    } else if(Std.downcast(astNode, SamalCreateEnumExpression) != null) {
                        var node = Std.downcast(astNode, SamalCreateEnumExpression);
                        final newType = complete(node.getDatatype().sure());
                        if(!newType.match(Usertype(_, _, Enum))) {
                            throw new Exception(node.errorInfo() + " The datatype declaration for this type is not an enum: " + newType);
                        }
                        node.setDatatype(newType);
                        
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
                        final newType = complete(node.getDatatype().sure());
                        if(!newType.match(Usertype(_, _, Struct))) {
                            throw new Exception(node.errorInfo() + " The datatype declaration for this type is not a struct: " + newType);
                        }
                        node.setDatatype(newType);
                        
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
        for(entry in mInstantiatedUserTypes) {
            final decl = mProgram.findDatatypeDeclaration(entry.originalTemplatedType);
            if(decl.getDatatype().isComplete())
                continue;

            final newDecl = decl.cloneWithTemplateParams(
                new StringToDatatypeMapperUsingTypeMap(Util.buildTemplateReplacementMap(decl.getTemplateParams(), entry.passedTemplateParams)), 
                entry.passedTemplateParams);
            mProgram.getModule(entry.module).sure().getDeclarations().push(newDecl);
        }

        // step 4: delete pure template structs
        mProgram.forEachModule(function(moduleName, moduleAST) {
            var newDecls = [];
            for(decl in moduleAST.getDeclarations()) {
                if(Std.downcast(decl, SamalDatatypeDeclaration) == null || decl.getDatatype().isComplete()) {
                    newDecls.push(decl);
                }
            }
            moduleAST.setDeclarations(newDecls);
        });
        return mProgram;
    }
}