#!/usr/bin/rdmd

import std.array;
import std.algorithm;
import std.path;
import std.process;
import std.stdio;
import std.getopt;

void main(string[] args)
{
    auto help = getopt(args);
    if (help.helpWanted || args.length != 3 || (args[1] != "tests" && args[1] != "benchmarks") || (args[2] != "ldc" && args[2] != "dmd" && args[2] != "gdc"))
    {
        writeln("USAGE: rdmd run tests|benchmarks ldc|dmd|gdc");
        return;
    }

    int model = detectModel();
    if (!model)
    {
        writeln("Failure to recognize OS model");
        return;
    }
    string compile, execute;

    if (args[2] == "ldc")
    {
        compile = "ldc2 -O3";
    }
    else if (args[2] == "dmd")
    {
        compile = "rdmd -O -inline"; 
    }
    else
    {
        compile = "gdc -O3";
    }

    if (model == 32)
    {
        compile ~= " -m32";
    }
    else
    {
        compile ~= " -m64";
    }

    if (args[2] == "dmd")
    {
        compile ~= " --build-only";
    }

    if (args[1] == "tests")
    {
        compile ~= " tests.d Dmemset.d";
        execute = "./tests";
        if (args[2] == "gdc")
        {
            compile ~= " -o tests";
        }
    }
    else
    {
        compile ~= " benchmarks.d Dmemset.d";
        if (args[2] == "gdc")
        {
            compile ~= " -o benchmarks";
        }
        execute = "./benchmarks";
    }

    if(run(compile) != 0)
    {
        return;
    }
    run(execute);
}

int run(string cmd)
{
    writeln(cmd);
    auto pid = spawnProcess(cmd.split(' '));
    return wait(pid);
}

string detectOS()
{
    version(Windows)
        return "windows";
    else version(OSX)
        return "osx";
    else version(linux)
        return "linux";
    else version(FreeBSD)
        return "freebsd";
    else version(OpenBSD)
        return "openbsd";
    else version(NetBSD)
        return "netbsd";
    else version(DragonFlyBSD)
        return "dragonflybsd";
    else version(Solaris)
        return "solaris";
    else
        static assert(0, "Unrecognized or unsupported OS.");
}

/**
Detects the host model
Returns: 32, 64 or 0 on failure
*/
int detectModel()
{
    string uname;
    if (detectOS == "solaris")
        uname = ["isainfo", "-n"].execute.output;
    else if (detectOS == "windows")
        uname = ["wmic", "OS", "get", "OSArchitecture"].execute.output;
    else
        uname = ["uname", "-m"].execute.output;

    if (!uname.find("x86_64", "amd64", "64-bit")[0].empty)
        return 64;
    if (!uname.find("i386", "i586", "i686", "32-bit")[0].empty)
        return 32;
    
    return 0;
}
