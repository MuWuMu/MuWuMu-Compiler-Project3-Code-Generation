# Project2-Parser

## Quick Start

    $make

## scanner.l 修改部分

*   修正部分comment辨識，原本在行號計算有問題
*   將辨認出的token以yylval，把實際字串傳遞給parser
    *   並return parser中定義的token，以傳遞兩邊對應的token

## 運行步驟

1.  Terminal中輸入$make，會直接編lex, yacc，並直接gcc編譯後，執行test.sd
2.  make完後依舊可以輸入$./parser /你要的測試程式/
3.  make clean以清除lex.yy.c, y.tab.c等檔案
    
