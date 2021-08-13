package tools;

import sys.io.File;

class EmbedRuntimes {
    static function main() {
        final prefix = "assets/";
        final outputDir = "src/samal/generated/";
        final files = ["samal_runtime.cpp", "samal_runtime.hpp", "samal_runtime.js"];
        var res = 'package samal.generated;\n\n';
        for(fileName in files) {
            final inputFile = File.read(prefix + fileName);
            final content = inputFile.readAll().toString();
            inputFile.close();
            final escapedContent = StringTools.replace(content, "'", "\\'");
            
            final className = "Embedded_" + StringTools.replace(fileName, ".", "_");
            res += 'class ${className} {
    public static function getContent() : String {
        return \'${escapedContent}\';
    }
}\n\n';
        }
        File.saveContent(outputDir + "Runtimes.hx", res);
    }
}