#include "code_generation.h"
#include <iostream>

void CodeGenerator::emitTabs() {
    for (int i = 0; i < tabCount; ++i) {
        out << "    ";
    }
}

CodeGenerator::CodeGenerator(const std::string &filename) {
    out.open(filename + ".jasm");
    emitClassStart(filename);
}

CodeGenerator::~CodeGenerator() {
    emitClassEnd();
    if (out.is_open()) {
        out.close();
    }
}

//-------------------------------------------------------------

void CodeGenerator::emitClassStart(const std::string &class_name) {
    out << "class " << class_name << std::endl;
    out << "{" << std::endl;
    increaseTab();
}

void CodeGenerator::emitClassEnd() {
    decreaseTab();
    emitTabs(); out << "}" << std::endl;
}

//-------------------------------------------------------------

void CodeGenerator::emitField(const std::string &name, const std::string &type, const std::string &value) {
    emitTabs(); out << "field static " << type << " " << name;
    if (!value.empty()) {
        out << " = " << value << std::endl;
    } else {
        out << std::endl;
    }
}

void CodeGenerator::emitMethod(const std::string &name, const std::string &returnType, const std::string &params) {
    emitTabs(); out << "method public static " << returnType << " " << name << "(" << params << ")" << std::endl;
    emitTabs(); out << "max_stack 15" << std::endl;
    emitTabs(); out << "max_locals 15" << std::endl;
}

void CodeGenerator::emitMethodStart() {
    emitTabs(); out << "{" << std::endl;
    increaseTab();
}

void CodeGenerator::emitMethodEnd() {
    decreaseTab();
    emitTabs(); out << "}" << std::endl;
}

void CodeGenerator::emitReturn() {
    emitTabs(); out << "return" << std::endl;
}
