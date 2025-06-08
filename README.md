# Project3-Code-Generation

## Quick Start

    $make

## Project2 已知問題

1.   在declaration時的type check，如: int a = 3.5; 要檢查出type dismatch
2.   非void的function call一定要有一個變數assign，如: a = fun1(x, y); (func1為有return type的function)
3.   for loop 和 foreach未完成
4.   把symbol table存value都砍掉，包括const
5.   if或loop等等後的單行statement也要是一個block(要有一個symbol table)

## 已修正

1, 4

## Project3不須做

1. floating-point numbers
2. READ statements
3. array declaration or uasge
4. string variables, i.e. no assignments to string variables. Only string constants and string literals are provided for uses in PRINT statements.
    
