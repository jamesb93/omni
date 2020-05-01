# MIT License
# 
# Copyright (c) 2020 Francesco Cameli
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#remove tables here and move isStrUpperAscii (and strutils) to another module
import macros, tables, strutils, omni_type_checker, omni_macros_utilities

#This is equal to the old isUpperAscii(str) function, which got removed from nim >= 1.2.0
proc isStrUpperAscii(s: string, skipNonAlpha: bool): bool  =
    var hasAtleastOneAlphaChar = false
    if s.len == 0: return false
    for c in s:
        if skipNonAlpha:
            var charIsAlpha = c.isAlphaAscii()
            if not hasAtleastOneAlphaChar:
                hasAtleastOneAlphaChar = charIsAlpha
            if charIsAlpha and (not isUpperAscii(c)):
                return false
        else:
            if not isUpperAscii(c):
                return false
    return if skipNonAlpha: hasAtleastOneAlphaChar else: true

#Node replacement for sample block
proc parse_sample_block(sample_block : NimNode) : NimNode {.compileTime.} =
    return nnkStmtList.newTree(
        nnkCall.newTree(
            newIdentNode("generate_inputs_templates"),
            newIdentNode("omni_inputs"),
            newLit(1),
            newLit(0)
        ),
        nnkCall.newTree(
            newIdentNode("generate_outputs_templates"),
            newIdentNode("omni_outputs")
        ),
        nnkForStmt.newTree(
            newIdentNode("audio_index_loop"),
            nnkInfix.newTree(
                newIdentNode(".."),
                newLit(0),
                nnkPar.newTree(
                    nnkInfix.newTree(
                        newIdentNode("-"),
                        newIdentNode("bufsize"),
                        newLit(1)
                    )
                )
            ),
            sample_block
        ),
        nnkLetSection.newTree(
            nnkIdentDefs.newTree(
                newIdentNode("audio_index_loop"),
                newEmptyNode(),
                newLit(0)
            )
        )
    )

#Find struct calls in a nnkCall and replace them with .new calls.
#To do so, pass a function call here. What is prduced is a when statement that checks
#if the function name + "_obj" is declared, meaning it's a struct constructor the user is trying to call.
#e.g.
# Phasor(0.0) -> when declared(Phasor_obj): Phasor.new(0.0) else: Phasor(0.0)
# myFunc(0.0) -> when declared(myFunc_obj): myFunc.new(0.0) else: myFunc(0.0)
proc findStructConstructorCall(code_block : NimNode) : NimNode {.compileTime.} =
    if code_block.kind != nnkCall:
        return code_block

    var 
        proc_call_ident = code_block[0]
        proc_call_ident_kind = proc_call_ident.kind

    if proc_call_ident_kind == nnkDotExpr:
        proc_call_ident = proc_call_ident[0]
        proc_call_ident_kind = proc_call_ident.kind
    
    if proc_call_ident_kind != nnkIdent and proc_call_ident_kind != nnkSym:
        return code_block

    let proc_call_ident_obj = newIdentNode(proc_call_ident.strVal() & "_obj")

    var proc_new_call =  nnkCall.newTree(
        newIdentNode("new"),
        proc_call_ident
    )

    for index2, arg in code_block.pairs():
        var arg_temp = arg
        if index2 == 0:
            continue
        
        #Find other constructors in the args of the call
        if arg_temp.kind == nnkCall:
            arg_temp = findStructConstructorCall(arg_temp)
        elif arg_temp.kind == nnkExprEqExpr:
            arg_temp[1] = findStructConstructorCall(arg_temp[1])
        
        proc_new_call.add(arg_temp)
    
    #echo astGenRepr proc_new_call

    let when_statement_struct_new = nnkWhenStmt.newTree(
        nnkElifExpr.newTree(
            nnkCall.newTree(
                newIdentNode("declared"),
                proc_call_ident_obj
            ),
            nnkStmtList.newTree(
                proc_new_call
            )
        ),
        nnkElseExpr.newTree(
            nnkStmtList.newTree(
                code_block
            )
        )
    )

    result = when_statement_struct_new

#========================================================================================================================================================#
# EVERYTHING HERE SHOULD BE REWRITTEN, I SHOULDN'T BE LOOPING OVER EVERY SINGLE THING RECURSIVELY, BUT ONLY CONSTRUCTS THAT COULD CONTAIN VAR ASSIGNMENTS
#========================================================================================================================================================#

proc parse_block_recursively_for_variables(code_block : NimNode, variable_names_table : TableRef[string, string], is_constructor_block : bool = false, is_perform_block : bool = false) : void {.compileTime.} =
    if code_block.len > 0:
        
        for index, statement in code_block.pairs():
            let statement_kind = statement.kind

            #If entry is a var/let declaration (meaning it's already been expressed directly in the code), add its entries to table
            if statement_kind == nnkVarSection or statement_kind == nnkLetSection:
                for var_decl in statement.children():
                    let var_name = var_decl[0].strVal()
                    variable_names_table[var_name] = var_name

            #Look for "build:" statement. If there are any, it's an error. Only at last position there should be one.
            if is_constructor_block:
                if statement_kind == nnkCall or statement_kind == nnkCommand:
                    let statement_first = statement[0]
                    if statement_first.kind == nnkIdent or statement_first.kind == nnkSym:
                        if statement_first.strVal() == "build":
                           error "init: the \'build\' call, if used, must only be one and at the last position of the \'init\' block."

            #a (no types, defaults to float)
            #[ 
            if statement_kind == nnkIdent:
                code_block[index] = nnkVarSection.newTree(
                    nnkIdentDefs.newTree(
                        statement,
                        newIdentNode("float"),
                        newEmptyNode()
                    )
                )  
            ]#

            #Return stmt kind
            if statement_kind == nnkReturnStmt:
                #empty return
                if statement.len < 1:
                    continue

                var 
                    return_content = statement[0]
                    return_content_kind = return_content.kind

                if return_content_kind == nnkCall:
                    var 
                        new_return_content = findStructConstructorCall(return_content)
                        new_return_stmt = nnkReturnStmt.newTree(
                            new_return_content
                        )

                    code_block[index] = new_return_stmt

            #a : float OR a = 0.5 OR a float = 0.5 OR a : float = 0.5 OR a float
            elif statement_kind == nnkCall or statement_kind == nnkAsgn or statement_kind == nnkCommand:
                
                if statement.len < 2:
                    continue

                var 
                    var_ident = statement[0]
                    var_misc  = statement[1]

                let var_ident_kind = var_ident.kind

                #If an ambiguous openSym... Take the first symbol
                if(var_ident_kind == nnkOpenSymChoice):
                    var_ident = var_ident[0]
                
                var is_no_colon_syntax = false

                #a float = 0.5
                if var_ident_kind == nnkCommand:
                    var_ident = var_ident[0]
                    
                    var_misc = nnkStmtList.newTree(
                        nnkAsgn.newTree(
                            statement[0][1],
                            statement[1]
                        )
                    )
                    
                    is_no_colon_syntax = true

                #a float
                if statement_kind == nnkCommand:
                    var_misc = nnkStmtList.newTree(
                        var_misc
                    )

                    is_no_colon_syntax = true

                #var_name (used only when var_ident is a nnkIdent type)
                #new_var_statement is the actually code replacement
                var 
                    var_name : string
                    new_var_statement : NimNode

                #If dot syntax ("a.b = Vector()") OR array syntax ("data[i] = Vector()").
                if var_ident_kind == nnkDotExpr or var_ident_kind == nnkBracketExpr:

                    #if assignment, a.b = 10, check type of a.b
                    if statement_kind == nnkAsgn:
                        var default_value = var_misc

                        #Find if the = is a nnkCall, if it's so: check if it's a constructor call to a struct.
                        #This is in fact an error, but it will be thrown at the later semantic typed check! 
                        if default_value.kind == nnkCall:
                            default_value = findStructConstructorCall(default_value)

                        new_var_statement = nnkStmtList.newTree(
                            nnkAsgn.newTree(
                                var_ident,
                                nnkCall.newTree(
                                    nnkCall.newTree(
                                        newIdentNode("typeof"),
                                        var_ident
                                    ),
                                    default_value
                                )
                            )
                        )

                    #Other kinds of dot expr, like function calls (myVec.set(0.1)). Just continue
                    else:
                        continue

                #Everything else, normal assignments / calls
                else:
                    
                    #Faulty variable definition
                    if var_ident_kind != nnkIdent and var_ident_kind != nnkSym:
                        error("Invalid variable declaration")

                    #var_name, only to be used when no nnkDotExpr is used. This here will always be a nnkIdent
                    var_name = var_ident.strVal()
                    
                    #If already there is an entry, skip. Keep the first found one.
                    #if variable_names_table.hasKey(var_name):
                    #    continue

                    #a : float or a : float = 0.0
                    if statement_kind == nnkCall or is_no_colon_syntax:
                        
                        #This is for a : float = 0.0 AND a : float
                        if var_misc.kind == nnkStmtList:
                            
                            if var_misc[0].kind == nnkAsgn: 
                                let specified_type = var_misc[0][0]  # : float
                                var default_value  = var_misc[0][1]  # = 0.0

                                #Find if the = is a nnkCall, if it's so: check if it's a constructor call to a struct
                                if default_value.kind == nnkCall:
                                    default_value = findStructConstructorCall(default_value)

                                new_var_statement = nnkVarSection.newTree(
                                    nnkIdentDefs.newTree(
                                        var_ident,
                                        specified_type,
                                        default_value
                                    )
                                )        

                            else:
                                let specified_type = var_misc[0]  # : float

                                #var a : float
                                new_var_statement = nnkVarSection.newTree(
                                    nnkIdentDefs.newTree(
                                        var_ident,
                                        specified_type,
                                        newEmptyNode()
                                    )
                                )
                        
                            #This is needed to avoid renaming stuff that already is templates, etc... in perform_block
                            #[
                                when declared("phase").not:
                                    phase : ...
                                else:
                                    {.fatal.} ...
                            ]#
                            new_var_statement = nnkStmtList.newTree(
                                nnkWhenStmt.newTree(
                                    nnkElifBranch.newTree(
                                        nnkDotExpr.newTree(
                                            nnkCall.newTree(
                                                newIdentNode("declared"),
                                                var_ident
                                            ),
                                            newIdentNode("not")
                                        ),
                                        nnkStmtList.newTree(
                                            new_var_statement
                                        )
                                    ),
                                    nnkElse.newTree(
                                        nnkStmtList.newTree(
                                            nnkPragma.newTree(
                                                nnkExprColonExpr.newTree(
                                                    newIdentNode("fatal"),
                                                    newLit("can't re-define variable \'" & $var_name & "\'. It's already been defined.")
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                
                    #a = 0.0
                    elif statement_kind == nnkAsgn:
                        
                        var default_value = var_misc

                        #Find if the = is a nnkCall, if it's so: check if it's a constructor call to a struct
                        if default_value.kind == nnkCall:
                            default_value = findStructConstructorCall(default_value)

                        #Prevent the user from defining out1, out2... etc...
                        var is_out_variable = false
                        if(var_name.startsWith("out")):
                            #out1 / out10
                            if var_name.len == 4:
                                if var_name[3].isDigit:
                                    is_out_variable = true
                            elif var_name.len == 5:
                                if var_name[3].isDigit and var_name[4].isDigit:
                                    is_out_variable = true
                        
                        #not an out1, out2..etc..
                        if not is_out_variable:
                            #var a = 0.0
                            new_var_statement = nnkVarSection.newTree(
                                nnkIdentDefs.newTree(
                                    var_ident,
                                    newEmptyNode(),
                                    default_value,
                                )
                            )

                            let
                                var_name_assignment = new_var_statement[0][0]
                                var_assign = new_var_statement[0][2]

                            #This is needed to avoid renaming stuff that already had been defined in a previous variable, templates, etc...
                            #[
                                when declared("phase").not:
                                    var phase = ...
                                else:
                                    phase = typeof(phase)(...)
                            ]#
                        
                            new_var_statement = nnkStmtList.newTree(
                                nnkWhenStmt.newTree(
                                    nnkElifBranch.newTree(
                                        nnkDotExpr.newTree(
                                            nnkCall.newTree(
                                                newIdentNode("declared"),
                                                var_ident
                                            ),
                                            newIdentNode("not")
                                        ),
                                        nnkStmtList.newTree(
                                            new_var_statement
                                        )
                                    ),
                                    nnkElse.newTree(
                                        nnkStmtList.newTree(
                                            nnkAsgn.newTree(
                                                var_name_assignment,
                                                nnkCall.newTree(
                                                    nnkCall.newTree(
                                                        newIdentNode("typeof"),
                                                        var_name_assignment
                                                    ),
                                                    var_assign
                                                )
                                            )
                                        )
                                    )
                                )
                            )

                        #out1 = ... (ONLY in perform / sample blocks)
                        else:
                            if is_perform_block:
                                let out_var = newIdentNode(var_name)
                                new_var_statement = nnkAsgn.newTree(
                                    out_var,
                                    nnkCall.newTree(
                                        nnkCall.newTree(
                                            newIdentNode("typeof"),
                                            out_var
                                        ),
                                        default_value
                                    )
                                )

                #Add var decl to code_block only if something actually has been assigned to it
                #If using a template (like out1 in sample), new_var_statement would be nil here
                if new_var_statement != nil:

                    #echo repr new_var_statement

                    code_block[index] = new_var_statement

                    #And also to table
                    variable_names_table[var_name] = var_name
            
            #echo repr code_block

            #Run the function recursively
            parse_block_recursively_for_variables(statement, variable_names_table, is_constructor_block, is_perform_block)
    
    #Reset at end of chain
    #[ else:
        running_index_seq = @[0] ]#

macro parse_block_for_variables*(code_block_in : untyped, is_constructor_block_typed : typed = false, is_perform_block_typed : typed = false, is_sample_block_typed : typed = false, bits_32_or_64_typed : typed = false) : untyped =
    var 
        #used to wrap the whole code_block in a block: statement to create a closed environment to be semantically checked, and not pollute outer scope with symbols.
        final_block = nnkBlockStmt.newTree().add(newEmptyNode())
        code_block  = code_block_in

    let 
        is_constructor_block = is_constructor_block_typed.boolVal()
        is_perform_block = is_perform_block_typed.boolVal()
        is_sample_block = is_sample_block_typed.boolVal()
        bits_32_or_64 = bits_32_or_64_typed.boolVal()
    
    #Using the global variable. Reset it at every call.
    var variable_names_table = newTable[string, string]()

    #Sample block without perform
    if is_sample_block:
        code_block = parse_sample_block(code_block)

    #Standard perform block (is_sample_block is false here too)
    elif is_perform_block:
        var found_sample_block = false
        
        for index, statement in code_block.pairs():
            if statement.kind == nnkCall:
                let var_ident = statement[0]
                let var_misc  = statement[1]
                
                #Look for the sample block inside of perform
                if var_ident.strVal == "sample":
                    let sample_block = var_misc

                    #Replace the sample: block with the new parsed one.
                    code_block[index] = parse_sample_block(sample_block)

                    found_sample_block = true

                    break
            
        #couldn't find sample block IN perform block
        if found_sample_block.not:
            error "perform: no \'sample\' block provided, or not at top level."
        
    
    #Remove new statement from the block before all syntactic analysis.
    #This is needed for this to work:
    #new:
    #   phase
    #   somethingElse
    #This build_statement will then be passed to the next analysis part in order to be re-added at the end
    #of all the parsing.
    var build_statement : NimNode
    if is_constructor_block:
        let code_block_last = code_block.last()
        if code_block_last.kind == nnkCall or code_block_last.kind == nnkCommand:
            let code_block_last_first = code_block_last[0]
            if code_block_last_first.kind == nnkIdent or code_block_last_first.kind == nnkSym:
                if code_block_last_first.strVal() == "build":
                    build_statement = code_block_last
                    code_block.del(code_block.len() - 1) #delete from code_block too. it will added back again later after semantic evaluation.
    
    #Look for var  declarations recursively in all blocks
    parse_block_recursively_for_variables(code_block, variable_names_table, is_constructor_block, is_perform_block)
    
    #Add all stuff relative to initialization for perform function:
    #[
        #Add the templates needed for Omni_UGenPerform to unpack variable names declared with "var" in cosntructor
        generateTemplatesForPerformVarDeclarations()

        #Cast the void* to UGen*
        let ugen = cast[ptr UGen](ugen_ptr)

        #cast ins and outs
        castInsOuts()

        #Unpack the variables at compile time. It will also expand on any Buffer types.
        unpackUGenVariables(UGen)
    ]#
    if is_perform_block:
        var castInsOuts_call = nnkCall.newTree()

        #true == 64, false == 32
        if bits_32_or_64:
            castInsOuts_call.add(newIdentNode("castInsOuts64"))
        else:
            castInsOuts_call.add(newIdentNode("castInsOuts32"))

        code_block = nnkStmtList.newTree(
            nnkCall.newTree(
                newIdentNode("generateTemplatesForPerformVarDeclarations")
            ),
            nnkLetSection.newTree(
                nnkIdentDefs.newTree(
                    newIdentNode("ugen"),
                    newEmptyNode(),
                    nnkCast.newTree(
                        nnkPtrTy.newTree(
                            newIdentNode("UGen")
                        ),
                        newIdentNode("ugen_ptr")
                    )
                )
            ),
            castInsOuts_call,
            nnkCall.newTree(
                newIdentNode("unpackUGenVariables"),
                newIdentNode("UGen")
            ),

            #Re-add code_block
            code_block
        )

    final_block.add(code_block)

    #echo repr code_block

    #echo variable_names_table

    #echo "CODE BLOCK"
    #echo astGenRepr code_block
    #echo astGenRepr final_block

    #echo repr final_block

    #Run the actual macro to subsitute structs with let statements
    return quote do:
        #Need to run through an evaluation in order to get the typed information of the block:
        parse_block_for_consts_and_structs(`final_block`, `build_statement`, `is_constructor_block_typed`, `is_perform_block_typed`)


#========================================================================================================================================================#
# EVERYTHING HERE SHOULD BE REWRITTEN, I SHOULDN'T BE LOOPING OVER EVERY SINGLE THING RECURSIVELY, BUT ONLY CONSTRUCTS THAT COULD CONTAIN VAR ASSIGNMENTS
#========================================================================================================================================================#

proc parse_block_recursively_for_consts_and_structs(typed_code_block : NimNode, templates_to_ignore : TableRef[string, string], is_perform_block : bool = false) : void {.compileTime.} =  
    #Look inside the typed block, which contains info about types, etc...
    for index, typed_statement in typed_code_block.pairs():
        #kind of current inspected block
        let typed_statement_kind = typed_statement.kind

        #Useless types to inspect, skip them
        if typed_statement_kind   == nnkEmpty:
            continue
        elif typed_statement_kind == nnkSym:
            continue
        elif typed_statement_kind == nnkIdent:
            continue

        #Look for templates to ignore
        #[
        if typed_statement_kind == nnkTemplateDef:
            let template_name = typed_statement[0].strVal()
            templates_to_ignore[template_name] = template_name
            continue
        ]#

        #If it's a function call
        if typed_statement_kind == nnkCall:
            if typed_statement[0].kind == nnkSym:
                
                let function_name = typed_statement[0].strVal()

                #Fix Data/Buffer access: from [] = (delay_data, phase, write_value) to delay_data[phase] = write_value
                if function_name == "[]=":                
                    var new_array_assignment : NimNode

                    #1 channel
                    if typed_statement[1].kind == nnkDotExpr:
                        new_array_assignment = nnkAsgn.newTree(
                            nnkBracketExpr.newTree(
                                typed_statement[1],
                                typed_statement[2]
                            ),
                            typed_statement[3]
                        )

                    #Multi channel
                    else:
                        let bracket_expr = nnkBracketExpr.newTree(typed_statement[1])
                        
                        #Extract indexes
                        for channel_index in 2..typed_statement.len-2:
                            bracket_expr.add(typed_statement[channel_index])

                        new_array_assignment = nnkAsgn.newTree(
                            bracket_expr,
                            typed_statement.last()
                        )
                    
                    if new_array_assignment != nil:
                        typed_code_block[index] = new_array_assignment

                #Check type of all arguments for other function calls (not array access related) 
                #Ignore function ending in _min_max (the one used for input min/max conditional)
                #THIS IS NOT SAFE! min_max could be assigned by user to another def
                elif typed_statement.len > 1 and not(function_name.endsWith("_min_max")):
                    for i, arg in typed_statement.pairs():
                        #ignore i == 0 (the function_name)
                        if i == 0:
                            continue
                        
                        let arg_type  = arg.getTypeInst().getTypeImpl()
                        
                        #Check validity of each argument to function
                        checkValidType(arg_type, $i, is_proc_call=true, proc_name=function_name)

        #Look for var sections
        elif typed_statement_kind == nnkVarSection:
            let var_symbol = typed_statement[0][0]
            let var_type   = var_symbol.getTypeInst().getTypeImpl()
            let var_name   = var_symbol.strVal()

            #Look for templates to ignore
            #[ 
            if templates_to_ignore.hasKey(var_name):
                echo "Found template: " & $var_name

                #echo astGenRepr typed_statement

                #If found one, remove the var statement (from the untyped section) and use assign instead
                #Look for position in untyped code of this var statement and replace it with assign
                    typed_code_block[index] = nnkAsgn.newTree(
                    newIdentNode(var_name),
                    typed_statement[0][2]
                ) 
            ]#

            #Check if it's a valid type
            checkValidType(var_type, var_name)
                
            #Look for consts: capital letters.
            if var_name.isStrUpperAscii(true):
                let old_statement_body = typed_code_block[index][0]

                #Create new let statement
                let new_let_statement = nnkLetSection.newTree(
                    old_statement_body
                )

                #Replace the entry in the untyped block, which has yet to be semantically evaluated.
                typed_code_block[index] = new_let_statement

            #Look for ptr types, structs
            if var_type.kind == nnkPtrTy:
                #Found a struct!
                if var_type.isStruct():
                    let old_statement_body = typed_code_block[index][0]

                    #Detect if it's a non-initialized struct variable (e.g "data Data[float]")
                    if old_statement_body.len == 3:
                        if old_statement_body[2].kind == nnkEmpty:
                            let error_var_name = old_statement_body[0]
                            error("\'" & $error_var_name & "\': structs must be instantiated on declaration.")
                        
                    #All good, create new let statement
                    let new_let_statement = nnkLetSection.newTree(
                        old_statement_body
                    )

                    #Replace the entry in the untyped block, which has yet to be semantically evaluated.
                    typed_code_block[index] = new_let_statement

        #Look for / , div , % , mod and replace them with safediv and safemod
        elif typed_statement_kind == nnkInfix:
            assert typed_statement.len == 3

            let 
                infix_symbol = typed_statement[0]
                infix_str    = infix_symbol.strVal()

            if infix_str == "/" or infix_str == "div":
                typed_code_block[index] = nnkCall.newTree(
                    newIdentNode("safediv"),
                    typed_statement[1],
                    typed_statement[2]
                )

            elif infix_str == "%" or infix_str == "mod":
                typed_code_block[index] = nnkCall.newTree(
                    newIdentNode("safemod"),
                    typed_statement[1],
                    typed_statement[2]
                )

        #Check validity of dot exprs
        elif typed_statement_kind == nnkDotExpr:
            let typed_code_block_kind = typed_code_block.kind
            
            #Spot if trying to assign something to a field of a struct which is a struct! This is an error
            if typed_code_block_kind == nnkAsgn:
                if isStruct(typed_statement):
                    error("\'" & typed_statement.repr & "\': trying to re-assign an already allocated struct field.")
        
        #Run function recursively
        parse_block_recursively_for_consts_and_structs(typed_statement, templates_to_ignore, is_perform_block)

#This allows to check for types of the variables and look for structs to declare them as let instead of var
macro parse_block_for_consts_and_structs*(typed_code_block : typed, build_statement : untyped, is_constructor_block_typed : typed = false, is_perform_block_typed : typed = false) : untyped =
    #Extract the body of the block: [0] is an emptynode
    var inner_block = typed_code_block[1].copy()

    #And also wrap it in a StmtList (if it wasn't a StmtList already)
    if inner_block.kind != nnkStmtList:
        inner_block = nnkStmtList.newTree(inner_block)

    #These are the values extracted from ugen. and general templates. They must be ignored, and their "var" / "let" statement status should be removed
    var templates_to_ignore = newTable[string, string]()
    
    let 
        is_constructor_block = is_constructor_block_typed.strVal() == "true"
        is_perform_block = is_perform_block_typed.strVal() == "true"

    #echo astGenRepr inner_block
    #echo repr inner_block

    parse_block_recursively_for_consts_and_structs(inner_block, templates_to_ignore, is_perform_block)
    
    #Dirty way of turning a typed block of code into an untyped:
    #Basically, what's needed is to turn all newSymNode into newIdentNode.
    #Sym are already semantically checked, Idents are not...
    #Maybe just replace Syms with Idents instead? It would be much safer than this...
    result = typedToUntyped(inner_block)

    #echo repr result

    #if constructor block, run the init_inner macro on the resulting block.
    if is_constructor_block:

        #If old untyped code in constructor constructor had a "build" call as last call, 
        #it must be the old untyped "build" call for all parsing to work properly.
        #Otherwise all the _let / _var declaration in UGen body are screwed
        #If build_statement is nil, it means that it wasn't initialized at it means that there
        #was no "build" call as last statement of the constructor block. Don't add it.
        if build_statement != nil and build_statement.kind != nnkNilLit:
            result.add(build_statement)

        
        #Run the whole block through the init_inner macro. This will build the actual
        #constructor function, and it will run the untyped version of the "build" macro.
        result = nnkCall.newTree(
            newIdentNode("init_inner"),
            nnkStmtList.newTree(
                result
            )
        )
    
    #echo astGenRepr inner_block
    #echo repr result 