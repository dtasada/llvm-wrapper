# Zag Project Documentation

This document provides a detailed explanation of the `zag` project, a compiler for a custom language with the `.zag` file extension. The compiler is written in Zig and transpiles Zag code to C.

## Project Structure

The project is organized into the following main components:

- **`build.zig`**: The build script for the project, which manages dependencies and defines build steps.
- **`src/main.zig`**: The entry point of the compiler.
- **`src/Lexer.zig`**: The lexical analyzer, responsible for tokenizing the source code.
- **`src/parser/`**: The parser, which builds an Abstract Syntax Tree (AST) from the tokens.
- **`src/compiler/`**: The transpiler, which generates C code from the AST.

## Program Flow

The compilation process follows a classic pipeline:

1.  **Lexical Analysis**: The source code is read and converted into a sequence of tokens.
2.  **Parsing**: The tokens are parsed to build an Abstract Syntax Tree (AST).
3.  **C Transpilation**: The AST is traversed to generate C code.
4.  **C Compilation**: An external C compiler is invoked to produce the final native executable.

### 1. Entry Point (`src/main.zig`)

The program execution starts in `src/main.zig`. The `main` function is responsible for:

-   Parsing command-line arguments using the `clap` library. The primary command is `build`.
-   Calling the `build` function to start the compilation process.

The `build` function in `src/main.zig` orchestrates the entire compilation pipeline:

1.  It reads the source file (currently hardcoded to `src/main.zag`).
2.  It initializes the `Lexer` with the source file content.
3.  It tokenizes the source file using the `Lexer`.
4.  It initializes the `Parser` with the generated tokens.
5.  It parses the tokens into an AST using the `Parser.parse()` method.
6.  It initializes the `Compiler` (the C transpiler) with the AST.
7.  It transpiles the AST into a C source file (`.c`) and a corresponding header file (`zag.h`) in the `.zag-out` directory using the `Compiler.emit()` method.
8.  Finally, it invokes a system C compiler (e.g., `cc`) to compile the generated C code into a native executable.

### 2. Lexical Analysis (`src/Lexer.zig`)

The `Lexer` is responsible for converting the raw source code into a stream of tokens.

-   **`Token`**: The `Token` enum in `src/Lexer.zig` defines all possible tokens in the language, such as identifiers, keywords, operators, and literals.
-   **`Lexer.tokenize()`**: This is the core function of the lexer. It iterates through the source code character by character and groups them into tokens. It also maintains a `source_map` to track the position of each token, which is crucial for error reporting.

### 3. Parsing (`src/parser/`)

The parser takes the stream of tokens from the `Lexer` and builds an Abstract Syntax Tree (AST). This project uses a Pratt parser, which is known for its elegance and efficiency in handling expression precedence.

-   **`src/parser/ast.zig`**: This file defines the structure of the AST. The `Statement`, `Expression`, and `Type` unions are the fundamental building blocks that represent the program's structure.

-   **`src/parser/Parser.zig`**: This is the core of the parser.
    -   It uses two main functions for parsing expressions: `nud` (null denotation) for tokens that appear at the beginning of an expression (e.g., literals, identifiers) and `led` (left denotation) for tokens that appear in the middle of an expression (e.g., binary operators).
    -   It uses lookup tables for statement and expression handlers, which makes the parser easily extensible.
    -   The `parseExpression` function is the heart of the Pratt parser, correctly handling operator precedence and associativity.
    -   **Note on Implementation**: The parser currently uses a hashing mechanism to map AST nodes to their source code positions. This can be fragile. A more robust approach would be to store position information directly within the AST nodes themselves.

-   **`src/parser/statements.zig` & `src/parser/expressions.zig`**: These files contain the logic for parsing specific language constructs. For example, `statements.zig` has functions for parsing `let` statements, `if` statements, and `while` loops. `expressions.zig` handles parsing of literals, variables, function calls, etc.

-   **`src/parser/TypeParser.zig`**: This is a specialized sub-parser for handling type annotations. It cleverly reuses the same Pratt parsing design to parse complex type expressions.

### 4. C Transpilation (`src/compiler/Compiler.zig`)

The `Compiler` is the final stage of the pipeline before handing off to a C compiler. It traverses the AST produced by the parser and generates C code.

-   **`Compiler.emit()`**: This is the main entry point for the transpiler. It iterates through the statements in the AST, calls `compileStatement` for each one to generate C code into a buffer, and then writes the buffer to a `.c` file. Finally, it invokes an external C compiler on the generated file.

-   **`compileStatement()` & `compileExpression()`**: These are recursive functions that walk the AST and generate the corresponding C code as a string.
    -   `compileStatement` handles statements like `let`, `if`, `while`, and `return`.
    -   `compileExpression` handles expressions like literals, binary operations, function calls, and variable access.

-   **`zag.h` Header**: The compiler generates a header file, `zag.h`, which contains C typedefs for primitive types (e.g., `i32`, `f64`) and macros to support Zag features that don't map directly to C, such as optionals (`__ZAG_OPTIONAL_TYPE`) and error unions (`__ZAG_ERROR_UNION_TYPE`). The generated `.c` files include this header.

-   **Symbol Table**: The compiler maintains a symbol table to keep track of variables, functions, and their C-translated names and types. It uses a stack of scopes to handle variable shadowing and lifetimes.

-   **C Compiler Invocation**: After generating the C source files, the compiler spawns a child process to run a system C compiler (like `/usr/bin/cc`), passing it the path to the generated file and flags to produce the final executable in the `.zag-out/bin` directory.

### 5. Build Process (`build.zig`)

The `build.zig` file defines how the project is built. It uses the Zig build system to:

-   Declare the executable and its entry point.
-   Manage dependencies, which include:
    -   `clap`: For command-line argument parsing.
    -   `pretty`: For debugging and pretty-printing.
-   Set up the necessary build and run steps.

## Tree-sitter Grammar (`tree-sitter-zag/`)

The project also includes a tree-sitter grammar for the `.zag` language, located in the `tree-sitter-zag/` directory. This grammar is used for syntax highlighting, code navigation, and other tooling features.

The grammar is defined in `tree-sitter-zag/grammar.js`. It is written in JavaScript and uses the tree-sitter DSL to define the language's syntax. The grammar is based on the parser in `src/parser/`, and it is designed to be as close as possible to the parser's behavior. The grammar defines rules for all the language's constructs, including statements, expressions, and types.
