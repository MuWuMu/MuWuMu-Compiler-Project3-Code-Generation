#ifndef CODE_GENERATION_H
#define CODE_GENERATION_H

#include <string>
#include <fstream>

class CodeGenerator {
public:
    CodeGenerator(const std::string &filename); 
    ~CodeGenerator();

    void emitClassStart(const std::string &class_name);
    void emitClassEnd();
    void emitField(const std::string &name, const std::string &type);
    void emitMethodStart(const std::string &name, const std::string &returnType, const std::string &params);
    void emitMethodEnd();
    void emitReturn();

    void increaseTab() { tabCount++; }
    void decreaseTab() { if (tabCount > 0) tabCount--; }
private:
    std::ofstream out;
    int tabCount = 0;
    void emitTabs();
};

#endif