package samal;

import samal.Program;

class Stage1 {
    var mProgram : SamalProgram;
    public function new(prog : SamalProgram) {
        mProgram = prog;
    }

    public function completeGlobalIdentifiers() : SamalProgram {
        return mProgram;
    }
}