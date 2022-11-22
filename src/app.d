module app;

import std.algorithm;
import std.array;
import std.getopt;
import std.json;
import std.process;
import std.stdio;
import std.typecons;

enum appVersion = "1.0.2";

struct Pack
{
    string name;
    string ver;
    string config;
    string[] overrideConfig;

    @property string dubId()
    {
        assert(name);
        if (ver)
            return name ~ "@" ~ ver;
        else
            return name;
    }
}

struct DubConfig
{
    string exe;
    string compiler;
    string arch;
    string build;

    string[] makeDescribeCmd(Pack pack)
    {
        return makeComplexCmd("describe", pack);
    }

    string[] makeBuildCmd(Pack pack)
    {
        return makeComplexCmd("build", pack);
    }

    string[] makeFetchCmd(Pack pack)
    {
        return [exe, "fetch", pack.dubId];
    }

    string[] makeComplexCmd(string cmdName, Pack pack)
    {
        auto cmd = [
            exe, cmdName, pack.dubId
        ];
        if (pack.config)
            cmd ~= ["--config", pack.config];

        foreach (oc; pack.overrideConfig)
            cmd ~= ["--override-config", oc];

        if (compiler)
            cmd ~= ["--compiler", compiler];

        if (arch)
            cmd ~= ["--arch", arch];

        if (build)
            cmd ~= ["--build", build];

        return cmd;
    }

}

int usage(string dbdExe, Option[] opts, int code = 0, string errorMsg = null)
{
    auto file = code == 0 ? stdout : stderr;

    if (errorMsg)
    {
        file.writefln("Error: %s", errorMsg);
        file.writeln("");
    }

    if (code == 0)
    {
        file.writefln("dub-build-deep v%s - An utility to build DUB sub-dependencies", appVersion);
        file.writefln("");
    }

    file.writefln("Usage:");
    file.writefln("    %s [options] (package name)[@version]", dbdExe);
    file.writeln();
    file.writeln("Most options are the same than expected by DUB describe.");

    defaultGetoptFormatter(file.lockingTextWriter(), null, opts);

    return code;
}

bool debug_;
bool quiet;

void logDebug(Args...)(string fmt, Args args)
{
    if (debug_)
        stdout.writefln(fmt, args);
}

void logInfo(Args...)(string fmt, Args args)
{
    if (!quiet)
        stdout.writefln(fmt, args);
}

void logWarning(Args...)(string fmt, Args args)
{
    if (!quiet)
        stderr.writefln("Warning: " ~ fmt, args);
}

void logError(Args...)(string fmt, Args args)
{
    stderr.writefln("Error: " ~ fmt, args);
}

int main(string[] args)
{
    Pack pack;

    DubConfig dub;
    dub.exe = "dub";

    // dfmt off
    auto helpInfo = getopt(args,
        "config", "Specify a DUB configuration", &pack.config,
        "override-config", "Specify a DUB configuration for a sub-dependency", &pack.overrideConfig,
        "dub", "Specify a DUB executable", &dub.exe,
        "compiler", "D compiler to be used", &dub.compiler,
        "arch", "Architecture to target", &dub.arch,
        "build", "The build type (debug, release, ...)", &dub.build,
        "debug", "Add debug output (all commands output streams)", &debug_,
        "quiet", "Decrease verbosity", &quiet,
    );
    // dfmt on

    if (helpInfo.helpWanted)
        return usage(args[0], helpInfo.options);

    if (args.length < 2)
        return usage(args[0], helpInfo.options, 1, "(package name] was not provided");

    if (args.length > 2)
        return usage(args[0], helpInfo.options, 1, "Too many arguments (only one package accepted)");

    const spec = args[1].split("@");
    if (spec.length > 2)
    {
        logError("Invalid package specifier: %s", args[1]);
        return 1;
    }
    pack.name = spec[0];
    if (spec.length == 2)
        pack.ver = spec[1];

    const describeCmd = dub.makeDescribeCmd(pack);

    logInfo("Getting description of %s", pack.dubId);
    auto describe = executeRedirect(describeCmd, Yes.allowFail);

    if (describe.status != 0 && describe.error.canFind("locally"))
    {
        logWarning("%s does not appear to be present locally.", pack.dubId);
        logInfo("Fetching %s", pack.dubId);
        const fetchCmd = dub.makeFetchCmd(pack);
        auto fetch = executeRedirect(fetchCmd, No.allowFail);
        if (fetch.status != 0)
            return fetch.status;

        logInfo("Getting description of %s", pack.dubId);
        describe = executeRedirect(describeCmd, No.allowFail);
    }

    if (describe.status != 0)
        return describe.status;

    auto json = parseJSON(describe.output);

    foreach (jp; json["packages"].array)
    {
        version (GNU)
        {
            if (!jp["active"].type == JSON_TYPE.TRUE)
            continue;
        }
        else
        {
            if (!jp["active"].boolean)
            continue;
        }

        const targetType = jp["targetType"].str;
        if (targetType == "none" || targetType == "sourceLibrary")
            continue;

        Pack p;
        p.name = jp["name"].str;
        p.ver = jp["version"].str;
        p.config = jp["configuration"].str;

        const res = buildDubPackage(p, dub);

        if (res)
            return res;
    }

    return 0;
}

int buildDubPackage(Pack pack, DubConfig dub)
{
    const buildCmd = dub.makeBuildCmd(pack);
    logInfo("Building %s@%s (config %s)", pack.name, pack.ver, pack.config);
    auto res = executeRedirect(buildCmd, No.allowFail);
    return res.status;
}

alias ExeResult = Tuple!(int, "status", string, "output", string, "error");

ExeResult executeRedirect(scope const(char[])[] cmd, Flag!"allowFail" allowFail)
{
    if (debug_)
        stdout.writefln("=== running `%s`", cmd.map!escapeSpace.join(" "));

    auto pipes = pipeProcess(cmd);

    auto output = appender!string();
    auto error = appender!string();

    foreach (ubyte[] chunk; pipes.stdout.byChunk(8192))
        output.put(chunk);
    foreach (ubyte[] chunk; pipes.stderr.byChunk(8192))
        error.put(chunk);

    int status = wait(pipes.pid);

    // exhaust if needed
    foreach (ubyte[] chunk; pipes.stdout.byChunk(8192))
        output.put(chunk);
    foreach (ubyte[] chunk; pipes.stderr.byChunk(8192))
        error.put(chunk);

    string outp = output.data;
    string err = error.data;

    if (allowFail || status == 0)
    {
        if (debug_)
        {
            stdout.writefln("=== status: %s", status);
            stdout.writeln("=== stdout:");
            stdout.write(outp);
            stdout.writeln("=== stderr:");
            stdout.write(err);
            stdout.writeln("===========");
        }
    }
    else
    {
        stderr.writefln("Error: Command failed: %s", cmd.map!escapeSpace.join(" "));
        stderr.writefln("=== status: %s", status);
        if (debug_)
        {
            stderr.writeln("=== stdout:");
            stderr.write(outp);
        }
        stderr.writefln("=== stderr:");
        stderr.write(err);
        stderr.writefln("===========");
    }

    return ExeResult(status, outp, err);
}

// escape space in a shell argument (only worth for debug print, not actual execution)
const(char)[] escapeSpace(const(char)[] arg)
{
    if (arg.canFind(" "))
        return `"` ~ arg ~ `"`;
    return arg;
}
