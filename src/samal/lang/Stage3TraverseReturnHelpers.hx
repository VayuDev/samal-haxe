package samal.lang;

import samal.lang.CppAST.CppStatement;

enum Stage3TraverseReturn {
    Literal(str : String);
    Statement(stmt : CppStatement);
}

class Stage3TraverseReturnHelpers {
    static public function str(ret : Stage3TraverseReturn) : String {
        switch(ret) {
        case Literal(str): 
            return str;
        case Statement(stmt): 
            return stmt.getVarName();
        }
    }
}