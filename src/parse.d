import std.algorithm;
import std.regex;
import std.stdio;
import std.string;

/// An xrandr output.
struct Output
{
    string name;
    bool connected;
    bool primary;
    Mode[] availableModes;
    Orientation[] availableOrientations;
}

/// A xrandr output mode.
struct Mode
{
    string name;
    bool preferred;
    bool current;
    Frequency[] availableFrequencies;
}

/// An xrandr output frequency.
struct Frequency
{
    string name;
    bool preferred;
    bool current;
}

/// An xrandr output orientation
enum Orientation : string
{
    normal = "normal",
    left = "left",
    inverted = "inverted",
    right = "right"
}

Orientation[] parseOrientations(in string str)
{
    Orientation[] result;

    if (str.canFind(`normal`))
        result ~= Orientation.normal;

    if (str.canFind(`left`))
        result ~= Orientation.left;

    if (str.canFind(`inverted`))
        result ~= Orientation.inverted;

    if (str.canFind(`right`))
        result ~= Orientation.right;

    return result;
}
unittest
{
    assert(parseOrientations(``) == []);
    assert(parseOrientations(`normal`) == [Orientation.normal]);
    assert(parseOrientations(`left right`) == [Orientation.left, Orientation.right]);
    assert(parseOrientations(`right left`) == [Orientation.left, Orientation.right]);
    assert(parseOrientations(`normal right inverted`) == [Orientation.normal, Orientation.inverted, Orientation.right]);
}

Frequency[] parseFrequencies(in string str)
{
    Frequency[] freqs;

    // Replace series of spaces by single spaces
    auto simplified = str.replaceAll(ctRegex!(`\s+`, `g`), " ").strip;

    // Merge '+' with its frequency
    simplified = simplified.replaceAll(ctRegex!(`\s\+`), "+");

    // Merge '*' with its frequency
    simplified = simplified.replaceAll(ctRegex!(`\s\*`), "*");

    // Split the line by frequency
    string[] afterSplit = simplified.split(ctRegex!(`\s`));

    // Traverse all frequencies
    foreach (freq; afterSplit)
    {
        auto m = freq.matchFirst(ctRegex!(`^(?P<value>\d+(?:\.\d+|))(?P<mark>\*|\+|\*\+|)$`));
        if (m.length > 0)
        {
            Frequency f = {name : m["value"],
                preferred : m["mark"].canFind(`+`),
                current : m["mark"].canFind(`*`)};

            freqs ~= f;
        }
    }

    return freqs;
}
unittest
{
    Frequency f60 = {name:"60.00", preferred:false, current:false};
    Frequency f60p = {name:"60.00", preferred:true, current:false};
    Frequency f50 = {name:"50.00", preferred:false, current:false};
    Frequency f50c = {name:"50.00", preferred:false, current:true};
    Frequency f40 = {name:"40", preferred:false, current:false};
    Frequency f40pc = {name:"40", preferred:true, current:true};
    assert(parseFrequencies(`      60.00  `) == [f60]);
    assert(parseFrequencies(`40`) == [f40]);
    assert(parseFrequencies(`       60.00    50.00    40  `) == [f60, f50, f40]);
    assert(parseFrequencies(`       60.00 +  50.00    40  `) == [f60p, f50, f40]);
    assert(parseFrequencies(`       60.00    50.00*   40  `) == [f60, f50c, f40]);
    assert(parseFrequencies(`       60.00    50.00    40*+`) == [f60, f50, f40pc]);
}



/// Splits a raw `xrandr --query` result by xrandr output
Output[] parseQuery(in string queryResult)
{
    Output[] parsedOutputs;
    auto screenRegex = ctRegex!(`^Screen\s+\d+.*$`);
    auto outputRegex = ctRegex!(`^(?P<name>\S+)\s+(?P<connStatus>connected|disconnected)\s+.*\((?P<orientations>.*)\).*$`);
    auto modeRegex = ctRegex!(`^\s+(?P<name>\S+(?P<frequencies>.+)\S*)\s*$`);

    // Split query result by line
    string[] byLine = queryResult.split(ctRegex!(`\n`));

    // Remove screens from the query result.
    auto withoutScreens = filter!(a => a.matchFirst(screenRegex).length == 0)(byLine);

    // Traverse lines
    bool outputFound;
    Output output;
    Mode mode;
    foreach(line; withoutScreens)
    {
        auto outputMatch = line.matchFirst(outputRegex);
        if (outputMatch.length > 0)
        {
            // New output found!
            if (outputFound)
            {
                // Store previous mode in the function result
                parsedOutputs ~= output;
            }
            outputFound = true;

            // Parse new output
            output.name = outputMatch["name"];
            output.connected = outputMatch["connStatus"] == "connected";
            output.primary = line.canFind(`primary`);
            output.availableOrientations = parseOrientations(outputMatch["orientations"]);
        }
        else
        {
            auto modeMatch = line.matchFirst(modeRegex);
            if (modeMatch.length > 0 && outputFound)
            {
                mode.name = modeMatch["name"];
                mode.preferred = line.canFind(`+`);
                mode.current = line.canFind(`*`);
                mode.availableFrequencies = parseFrequencies(modeMatch["frequencies"]);
            }
        }
    }

    if (outputFound)
        parsedOutputs ~= output;

    return parsedOutputs;
}
unittest
{
    auto xrandrOutput = `Screen 0: minimum 8 x 8, current 1600 x 900, maximum 32767 x 32767
eDP1 connected primary 1600x900+0+0 (normal left inverted right x axis y axis) 310mm x 170mm
   1920x1080     60.06 +  59.93    40.04  
   1680x1050     59.88  
   1600x900      60.00*   59.95    59.82  
DP1 disconnected (normal left inverted right x axis y axis)
DP2 disconnected (normal inverted)`;

    Mode mode0 = {name:"1920x1080", preferred:true, availableFrequencies:[
        {name:"60.06", preferred:true,  current:false},
        {name:"59.93", preferred:false, current:false},
        {name:"40.04", preferred:false, current:false}]};
    Mode mode1 = {name:"1680x1050", preferred:false, availableFrequencies:[
        {name:"59.88", preferred:false}]};
    Mode mode2 = {name:"1600x900", preferred:false, availableFrequencies:[
        {name:"60.00", preferred:false, current:true},
        {name:"59.95", preferred:false, current:false},
        {name:"59.82", preferred:false, current:false}]};

    Output edp1 = {name: "eDP1", primary:true, connected:true,
        availableModes: [mode0, mode1, mode2],
        availableOrientations: [Orientation.normal, Orientation.left,
                                Orientation.inverted, Orientation.right]};
    Output dp1 = {name: "DP1", primary:false, connected:false,
        availableModes: [],
        availableOrientations: [Orientation.normal, Orientation.left,
                                Orientation.inverted, Orientation.right]};
    Output dp2 = {name: "DP2", primary:false, connected:false,
        availableModes: [],
        availableOrientations: [Orientation.normal, Orientation.inverted]};

    auto r = parseQuery(xrandrOutput);
    assert(r == r);
}
