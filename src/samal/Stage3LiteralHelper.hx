package samal;

abstract class Stage3LiteralHelper {
    abstract public function int(value : Int) : String;
    abstract public function emptyList() : String;
}

class Stage3LiteralHelperCpp extends Stage3LiteralHelper {
    public function new() {}

    public function int(value : Int) : String {
        return "(int32_t) (" + Std.string(value) + "ll)";
    }
    public function emptyList() : String {
        return "nullptr";
    }
}