package samal.bootstrap;

class CompileConfig {
    private static var mInstance = new CompileConfig();
    private var mShouldThrowErrors = true;

    private function new() {

    }
    public static function get() : CompileConfig {
        return mInstance;
    }
    public function shouldThrowErrors() {
        return mShouldThrowErrors;
    }
}