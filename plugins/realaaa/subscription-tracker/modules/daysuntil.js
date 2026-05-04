/*\
title: $:/plugins/realaaa/subscription-tracker/modules/daysuntil.js
type: application/javascript
module-type: filteroperator

Filter operator: for each input title interpreted as a TiddlyWiki date string
(YYYYMMDDhhmmsssss), returns the integer number of UTC days from today until
that date. Negative for past dates. Skips unparseable inputs.

Why a JS module: TW 5.4 core does not provide a date-math primitive that
returns days-between-dates. The auto-roll renewal-date feature (spec §5.3,
§7.6) and the renewal-soon highlighting both need this. Keeping the
implementation in-plugin (rather than depending on a third-party plugin)
preserves the dependency-free goal.

\*/
"use strict";

exports.daysuntil = function(source, operator, options) {
    var results = [];
    var now = new Date();
    var nowUtc = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
    var msPerDay = 24 * 60 * 60 * 1000;
    source(function(tiddler, title) {
        var d = $tw.utils.parseDate(title);
        if (d && $tw.utils.isDate(d) && d.toString() !== "Invalid Date") {
            var thenUtc = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
            results.push(String(Math.round((thenUtc - nowUtc) / msPerDay)));
        }
    });
    return results;
};
