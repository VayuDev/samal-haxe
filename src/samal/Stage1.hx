package samal;

class Stage1 {
    var mProgram : Program;
    public function new(prog : Program) {
        mProgram = prog;
    }

    public function completeGlobalIdentifiers() : Program {
        return mProgram;
    }
}