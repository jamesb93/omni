#Path to nim file to compile

#Option to keep source files

#Build flags (native, x86-64, etc...)

#Supernova (default = true)

import cligen, terminal, os, strutils, dynlib

include "SC/Static/Nim_PROTO.cpp.nim"
include "SC/Static/CMakeLists.txt.nim"
include "SC/Static/Nim_PROTO.sc.nim"

const nimcollider_ver = "0.1.0"

#Default to the nimcollider nimble folder, which should have it installed if nimcollider has been installed correctly
const default_sc_path = "~/.nimble/pkgs/nimcollider-" & nimcollider_ver & "/deps/supercollider"

when defined(Linux):
    const default_extensions_path = "~/.local/share/SuperCollider/Extensions"
    const shared_lib_extension = "so"

when defined(MacOS):
    const default_extensions_path = "~/Library/Application\\ Support/SuperCollider/Extensions"
    const shared_lib_extension = "dylib"

type
    get_ugen_inputs_fun     = proc() : int32 {.gcsafe, stdcall.}
    get_ugen_outputs_fun    = proc() : int32 {.gcsafe, stdcall.}
    get_ugen_input_namesfun = proc() : ptr cchar {.gcsafe, stdcall.}

proc printErrorMsg(msg : string) : void =
    setForegroundColor(fgRed)
    writeStyled("ERROR: ", {styleBright}) 
    setForegroundColor(fgWhite, true)
    writeStyled(msg)

proc supernim(file : seq[string], sc_path : string = default_sc_path, extensions_path : string = default_extensions_path, architecture : string = "native", supernova : bool = false, remove_temp_dir : bool = true) : void = 

    #Check it's just a single path as positional argument
    if file.len != 1:
        printErrorMsg("Expected a single path to a .nim file as the only positional argument.")
        return

    let fullPath = absolutePath(file[0])

    #Check if file exists
    if not fullPath.existsFile():
        printErrorMsg($fullPath & " doesn't exist.")
        return
    
    var 
        nimFile     = splitFile(fullPath)
        nimFileDir  = nimFile.dir
        nimFileName = nimFile.name
        nimFileExt  = nimFile.ext

    #Check file first charcter, must be a capital letter
    if not nimFileName[0].isUpperAscii:
        nimFileName[0] = nimFileName[0].toUpperAscii()

    #Check file extension
    if not (nimFileExt == ".nim"):
        printErrorMsg($nimFileName & " is not a nim file.")
        return

    let expanded_sc_path = sc_path.expandTilde()

    #Check sc_path
    if not expanded_sc_path.existsDir():
        printErrorMsg($sc_path & " doesn't exist.")
        return
    
    let expanded_extensions_path = extensions_path.expandTilde()

    #Check extensions_path
    if not expanded_extensions_path.expandTilde().existsDir():
        printErrorMsg($extensions_path & " doesn't exist.")
        return

    #Full paths to the new file in nimFileName directory
    let 
        fullPathToNewFolder = $nimFileDir & "/" & $nimFileName

        #This is to use in shell cmds instead of fullPathToNewFolder, expands spaces to "\ "
        fullPathToNewFolderShell = fullPathToNewFolder.replace(" ", "\\ ")

        fullPathToNimFile   = $fullPathToNewFolder & "/" & $nimFileName & ".nim"
        
        #This is to use in shell cmds instead of fullPathToNimFile, expands spaces to "\ "
        fullPathToNimFileShell = fullPathToNimFile.replace(" ", "\\ ")

        fullPathToCppFile   = $fullPathToNewFolder & "/" & $nimFileName & ".cpp"
        fullPathToSCFile    = $fullPathToNewFolder & "/" & $nimFileName & ".sc" 
        fullPathToCMakeFile = $fullPathToNewFolder & "/" & "CMakeLists.txt"
    
    #Create directory in same folder as .nim file
    removeDir(fullPathToNewFolder)
    createDir(fullPathToNewFolder)

    #Copy nimFile to folder
    copyFile(fullPath, fullPathToNimFile)

    # ================ #
    # COMPILE NIM FILE #
    # ================ #

    #Compile nim file. Only pass the -d:supernim and -d:tempDir flag here, so it generates the IO.txt file.
    let failedNimCompilation = execShellCmd("nim c --import:nimcollider --app:lib --gc:none --noMain:on --passC:-march=" & $architecture & " -d:supernim -d:tempDir=" & $fullPathToNewFolderShell & " -d:supercollider -d:release -d:danger --checks:off --assertions:off --opt:speed --outdir:" & $fullPathToNewFolderShell & "/lib " & $fullPathToNimFileShell)
    
    if failedNimCompilation == 1:
        printErrorMsg("Unsuccessful compilation of " & $nimFileName & ".nim")
        return
    
    #Also for supernova
    if supernova:
        let failedNimCompilation_supernova = execShellCmd("nim c --import:nimcollider --app:lib --gc:none --noMain:on --passC:-march=" & $architecture & " -d:supernova -d:release -d:danger --checks:off --assertions:off --opt:speed --out: lib" & $nimFileName & "_supernova." & $shared_lib_extension & " --outdir:" & $fullPathToNewFolderShell & "/lib " & $fullPathToNimFileShell)
        
        if failedNimCompilation_supernova == 1:
            printErrorMsg("Unsuccessful supernova compilation of " & $nimFileName & ".nim")
            return
    
    # ================ #
    #  RETRIEVE I / O  #
    # ================ #
    
    let 
        io_file = readFile($fullPathToNewFolder & "/IO.txt")
        io_file_seq = io_file.split('\n')

    if io_file_seq.len != 3:
        printErrorMsg("Invalid IO.txt file")
        return   
    
    let 
        num_inputs  = parseInt(io_file_seq[0])
        input_names_string = io_file_seq[1]
        input_names = input_names_string.split(',') #this is a seq now
        num_outputs = parseInt(io_file_seq[2])

    #[
    echo num_inputs
    echo input_names
    echo num_outputs 
    ]#

    # ================ #
    # CREATE NEW FILES #
    # ================ #

    #Create .ccp/.sc/cmake files in the new folder
    let
        cppFile   = open(fullPathToCppFile, fmWrite)
        scFile    = open(fullPathToSCFile, fmWrite)
        cmakeFile = open(fullPathToCMakeFile, fmWrite)
    
    # ======== #
    # SC I / O #
    # ======== #
    
    var 
        arg_string = ""
        arg_rates = ""
        multiNew_string = "^this.multiNew('audio'"
        multiOut_string = ""

    #No input names
    if input_names[0] == "__NO_PARAM_NAMES__":
        if num_inputs == 0:
            multiNew_string.add(");")
        else:
            arg_string.add("arg ")
            multiNew_string.add(",")
            
            for i in 1..num_inputs:

                arg_rates.add("if(in" & $i & ".rate != 'audio', { (\"argument number " & $i & " must be audio rate\").warn; ^Silent.ar; });\n\t\t")

                if i == num_inputs:
                    arg_string.add("in" & $i & ";")
                    multiNew_string.add("in" & $i & ");")
                    break

                arg_string.add("in" & $i & ", ")
                multiNew_string.add("in" & $i & ", ")
        
    #input names
    else:
        if num_inputs == 0:
            multiNew_string.add(");")
        else:
            arg_string.add("arg ")
            multiNew_string.add(",")
            for index, input_name in input_names:

                arg_rates.add("if(" & $input_name & ".rate != 'audio', { (\"argument number " & $(index + 1) & " must be audio rate\").warn; ^Silent.ar; });\n\t\t")

                if index == num_inputs - 1:
                    arg_string.add($input_name & ";")
                    multiNew_string.add($input_name & ");")
                    break

                arg_string.add($input_name & ", ")
                multiNew_string.add($input_name & ", ")

    
    NIM_PROTO_SC = NIM_PROTO_SC.replace("//args", arg_string)
    NIM_PROTO_SC = NIM_PROTO_SC.replace("//rates", arg_rates)
    NIM_PROTO_SC = NIM_PROTO_SC.replace("//multiNew", multiNew_string)

    #Multiple outputs UGen
    if num_outputs > 1:
        multiOut_string = "init { arg ... theInputs;\n\t\tinputs = theInputs;\n\t\t^this.initOutputs(" & $num_outputs & ", rate);\n\t}"
        NIM_PROTO_SC = NIM_PROTO_SC.replace("//multiOut", multiOut_string)
        NIM_PROTO_SC = NIM_PROTO_SC.replace(" : UGen", " : MultiOutUGen")

    # =========== #
    # WRITE FILES #
    # =========== #

    #Replace Nim_PROTO with the name of the Nim file
    NIM_PROTO_CPP   = NIM_PROTO_CPP.replace("Nim_PROTO", nimFileName)
    NIM_PROTO_SC    = NIM_PROTO_SC.replace("Nim_PROTO", nimFileName)
    NIM_PROTO_CMAKE = NIM_PROTO_CMAKE.replace("Nim_PROTO", nimFileName)

    cppFile.write(NIM_PROTO_CPP)
    scFile.write(NIM_PROTO_SC)
    cmakeFIle.write(NIM_PROTO_CMAKE)

    cppFile.close
    scFile.close
    cmakeFIle.close
    
    # ========== #
    # BUILD UGEN #
    # ========== #

    #Create build folder
    removeDir($ fullPathToNewFolder & "/build")
    createDir($ fullPathToNewFolder & "/build")

    var sc_cmake_cmd : string
    
    if supernova:
        sc_cmake_cmd = "cd " & $fullPathToNewFolderShell & "/build && cmake -DWORKING_FOLDER=" & $fullPathToNewFolderShell & " -DSC_PATH=" & $expanded_sc_path & " -DSUPERNOVA=ON -DCMAKE_BUILD_TYPE=Release -DBUILD_MARCH=" & $architecture & " .."
    else:
        sc_cmake_cmd = "cd " & $fullPathToNewFolderShell & "/build && cmake -DWORKING_FOLDER=" & $fullPathToNewFolderShell & " -DSC_PATH=" & $expanded_sc_path & " -DCMAKE_BUILD_TYPE=Release -DBUILD_MARCH=" & $architecture & " .."

    let failedSCCmake = execShellCmd(sc_cmake_cmd)

    if failedSCCmake == 1:
        printErrorMsg("Unsuccessful cmake generation of the UGen file " & $nimFileName & ".cpp")
        return

    let sc_compilation_cmd = "cd " & $fullPathToNewFolderShell & "/build && make"

    let failedSCCompilation = execShellCmd(sc_compilation_cmd)

    if failedSCCompilation == 1:
        printErrorMsg("Unsuccessful compilation of the UGen file " & $nimFileName & ".cpp")
        return

    # ========================= #
    # COPY TO EXTENSIONS FOLDER #
    # ========================= #
    when defined(Linux):
        copyFile($fullPathToNewFolder & "/build/" & $nimFileName & ".so", $fullPathToNewFolder & "/" & $nimFileName & ".so")
        if supernova:
            copyFile($fullPathToNewFolder & "/build/" & $nimFileName & "_supernova.so", $fullPathToNewFolder & "/" & $nimFileName & "_supernova.so")

    when defined(MacOS):
        copyFile($fullPathToNewFolder & "/build/" & $nimFileName & ".scx", $fullPathToNewFolder & "/" & $nimFileName & ".scx")
        if supernova:
            copyFile($fullPathToNewFolder & "/build/" & $nimFileName & "_supernova.scx", $fullPathToNewFolder & "/" & $nimFileName & "_supernova.scx")

    #Remove build, .cpp, cmake, .nim
    removeDir($fullPathToNewFolder & "/build")
    removeFile(fullPathToCppFile)
    removeFile(fullPathToNimFile)
    removeFile(fullPathToCMakeFile)

    #Copy to extensions folder
    let fullPathToNewFolderInExtenstions = $expanded_extensions_path  & "/" & nimFileName
    
    #Remove previous folder there if there was, then copy the new one
    removeDir(fullPathToNewFolderInExtenstions)
    copyDir($fullPathToNewFolder, fullPathToNewFolderInExtenstions)

    #Remove temp folder
    if remove_temp_dir:
        removeDir(fullPathToNewFolder)

    setForegroundColor(fgGreen, true)
    writeStyled("DONE!")

    

#Dispatch the supernim function as the CLI one
dispatch(supernim, 
    short={"sc_path" : 'p', "supernova" : 's'}, 
    
    help={ "sc_path" : "Path to the SuperCollider source code folder.", 
           "extensions_path" : "Path to SuperCollider's \"Platform.userExtensionDir\" or \"Platform.systemExtensionDir\".\n",
           "architecture" : "Build architecture.",
           "supernova" : "Build with supernova support."
    }

)