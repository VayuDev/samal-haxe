package samal.targets;
import samal.targets.LanguageTarget;

class JSContext extends SourceCreationContext {
    public override function next() : JSContext {
        return new JSContext(mIndent + 1, mMainFunction);
    }
    public override function prev() : JSContext {
        return new JSContext(mIndent - 1, mMainFunction);
    }
}