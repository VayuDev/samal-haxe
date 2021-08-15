package samal.bootstrap;

class BootstrapUtils {
    public static function escapeString(str : String) {
        var ret = "";
        for(i in 0...str.length) {
            var ch = str.charAt(i);
            switch(ch) {
                case "\n":
                    ret += "\\n";
                case _:
                    ret += ch;
            }
        }
        return ret;
    }
}