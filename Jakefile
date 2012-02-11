/*
 * Jakefile
 * WyzihatKit
 *
 * Created by Alexander Ljungberg on April 14, 2010.
 * Copyright 2010, WireLoad, LLC All rights reserved.
 */

var ENV = require("system").env,
    FILE = require("file"),
    JAKE = require("jake"),
    task = JAKE.task,
    FileList = JAKE.FileList,
    framework = require("cappuccino/jake").framework,
	browserEnvironment = require("objective-j/jake/environment").Browser,
    configuration = ENV["CONFIG"] || ENV["CONFIGURATION"] || ENV["c"] || "Debug",
    OS = require("os");

framework ("wyzihatkit", function(task)
{
    task.setBuildIntermediatesPath(FILE.join("Build", "wyzihatkit.build", configuration));
    task.setBuildPath(FILE.join("Build", configuration));

    task.setProductName("WyzihatKit");
    task.setIdentifier("wyzihatkit");
    task.setVersion("1.0");
    task.setAuthor("Alexander Ljungberg");
    task.setEmail("aljungberg@wireload.net");
    task.setSummary("WyzihatKit");
    task.setSources((new FileList("**/*.j")).exclude(FILE.join("Build", "**")).exclude(FILE.join("sample", "**")).exclude(FILE.join("sample.dist", "**")));
    task.setResources(new FileList("Resources/**"));
    task.setInfoPlistPath("Info.plist");
	
	task.setEnvironments([browserEnvironment]);
	task.setFlattensSources(true);

    if (configuration === "Debug")
        task.setCompilerFlags("-DDEBUG -g");
    else
        task.setCompilerFlags("-O");
	
});

function printResults(configuration)
{
    print("----------------------------");
    print(configuration+" app built at path: "+FILE.join("Build", configuration, "WyzihatKit"));
    print("----------------------------");
}

task ("default", ["wyzihatkit"], function()
{
    printResults(configuration);
});

task ("build", ["default"]);

task ("debug", function()
{
    ENV["CONFIGURATION"] = "Debug";
    JAKE.subjake(["."], "build", ENV);
});

task ("release", function()
{
    ENV["CONFIGURATION"] = "Release";
    JAKE.subjake(["."], "build", ENV);
});

task ("run", ["debug"], function()
{
    OS.system(["open", FILE.join("Build", "Debug", "wyzihatkit", "index.html")]);
});

task ("run-release", ["release"], function()
{
    OS.system(["open", FILE.join("Build", "Release", "wyzihatkit", "index.html")]);
});

task ("deploy", ["release"], function()
{
    FILE.mkdirs(FILE.join("Build", "Deployment", "wyzihatkit"));
    OS.system(["press", "-f", FILE.join("Build", "Release", "wyzihatkit"), FILE.join("Build", "Deployment", "wyzihatkit")]);
    printResults("Deployment")
});
