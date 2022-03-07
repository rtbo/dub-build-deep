module app;

import std.algorithm;
import std.array;
import std.getopt;
import std.json;
import std.process;
import std.stdio;

enum dbdVersion = "1.0.2";

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
        file.writefln("dub-build-deep v%s - An utility to build DUB sub-dependencies", dbdVersion);
        file.writefln("");
    }

    file.writefln("Usage:");
    file.writefln("    %s [options] (package name)[@version]", dbdExe);
    file.writeln();
    file.writeln("Most options are the same than expected by DUB describe.");

    defaultGetoptFormatter(file.lockingTextWriter(), null, opts);

    return code;
}

int main(string[] args)
{
    Pack pack;

    DubConfig dub;
    dub.exe = "dub";

    auto helpInfo = getopt(args,
        "config", "Specify a DUB configuration", &pack.config,
        "override-config", "Specify a DUB configuration for a sub-dependency", &pack.overrideConfig,
        "dub", "Specify a DUB executable", &dub.exe,
        "compiler", "D compiler to be used", &dub.compiler,
        "arch", "Architecture to target", &dub.arch,
        "build", "The build type (debug, release, ...)", &dub.build,
    );

    if (helpInfo.helpWanted)
    {
        return usage(args[0], helpInfo.options);
    }

    if (args.length < 2)
    {
        return usage(args[0], helpInfo.options, 1, "(package name] was not provided");
    }

    if (args.length > 2)
    {
        return usage(args[0], helpInfo.options, 1, "Too many arguments (only one package accepted)");
    }

    const spec = args[1].split("@");
    if (spec.length > 2)
    {
        stderr.writeln("Invalid package specifier: ", args[1]);
        return 1;
    }
    pack.name = spec[0];
    if (spec.length == 2)
    {
        pack.ver = spec[1];
    }

    const describeCmd = dub.makeDescribeCmd(pack);

    writeln("running ", escapeShellCommand(describeCmd));
    auto describe = execute(describeCmd);

    if (describe.status != 0 && describe.output.canFind("locally"))
    {
        writefln("Warning: %s does not appear to be present locally. Will try to fetch...", pack.dubId);
        const fetchCmd = dub.makeFetchCmd(pack);
        writefln("running %s", escapeShellCommand(fetchCmd));
        auto fetch = execute(fetchCmd);
        if (fetch.status != 0)
        {
            stderr.writefln("Error: `dub fetch` returned %s:", fetch.status);
            stderr.writeln(fetch.output);
            return fetch.status;
        }

        writeln("running ", escapeShellCommand(describeCmd));
        describe = execute(describeCmd);
    }


    if (describe.status != 0)
    {
        stderr.writeln("Error: describe command returned %s:", describe.status);
        stderr.writeln(describe.output);
        return describe.status;
    }

    auto json = parseJSON(describe.output);

    foreach (jp; json["packages"].array)
    {
        version(GNU)
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
    writeln("running ", escapeShellCommand(buildCmd));
    auto res = execute(buildCmd);
    if (res.status != 0)
    {
        stderr.writeln(res.output);
    }
    return res.status;
}
