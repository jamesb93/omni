#include "SC_PlugIn.h"

#include "NimCmds.hpp"

struct Nim : public Unit 
{
    void* sine_nim_obj;
};

static void Nim_next(Nim* unit, int inNumSamples);
static void Nim_Ctor(Nim* unit);
static void Nim_Dtor(Nim* unit);

void Nim_Ctor(Nim* unit) 
{
    if(Nim_UGenConstructor)
        unit->sine_nim_obj = (void*)Nim_UGenConstructor(unit->mInBuf);
    else
    {
        Print("ERROR: No libsine.so/dylib loaded\n");
        unit->sine_nim_obj = nullptr;
    }

    SETCALC(Nim_next);
    
    Nim_next(unit, 1);
}

void Nim_Dtor(Nim* unit) 
{
    if(unit->sine_nim_obj)
        Nim_UGenDestructor(unit->sine_nim_obj);
}

void Nim_next(Nim* unit, int inNumSamples) 
{
    if(unit->sine_nim_obj)
        Nim_UGenPerform(unit->sine_nim_obj, inNumSamples, unit->mInBuf, unit->mOutBuf);
    else
    {
        for(int i = 0; i < unit->mNumOutputs; i++)
        {
            for(int y = 0; y < inNumSamples; y++)
                unit->mOutBuf[i][y] = 0.0f;
        }
    }
}

PluginLoad(NimUGens) 
{
    ft = inTable; 

    retrieve_NimCollider_dir();
    
    DefineNimCmds();
    DefineDtorUnit(Nim);
}